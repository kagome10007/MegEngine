#include <cuda_runtime.h>

#include <stdio.h>
#include "./imma8832_256x64.cuh"
#include "./kern.cuh"
#include "./macro.cuh"
#include "./tools.cuh"

using namespace convolution;

namespace {
extern "C" __global__ void __launch_bounds__(256)
        ampere_conv_bias_uint4_int4_imma8832_ldg16_256x64_relu(
                const int8_t* __restrict__ src, int8_t* __restrict__ filter,
                const float* __restrict__ bias, int8_t* __restrict__ dst, float alpha,
                float beta, uint32_t pk_src_zero_point, float dst_zero_point,
                uint32_t relu, Conv2dInt4Param param,
                Conv2dConstantOffset conv2d_constant) {
#ifdef SM80_ENABLED
    const uint32_t tid = threadIdx.x;
    const uint32_t bidx = blockIdx.x;
    const uint32_t bidy = blockIdx.y;

    __shared__ int32_t smem[10240];  // (64+256)*128/8*2
    int2 reg_acc[reg_m][reg_n];
    int4 reg_src[2][reg_nd4];
    int4 reg_flt[2][reg_md4];
    // use in other way, maybe use reg_ser/flt
    int4 reg_src_cache[8];
    int4 reg_filter_cache[2];

    uint32_t tid127 = (tid & 127);
    uint32_t section = (tid127 >> 1);
    uint32_t residue = ((tid127 << 5) & 63);
    uint32_t nhw = bidx * BN + section;

    uint32_t tn, hw, toh, tow;
    int tih, tiw;
    int h_start[4];
    int h_end[4];
    int w_start[4];
    int w_end[4];
    bool g[4];
    const int8_t* __restrict__ g_src_ptr[8];
    for (int i = 0; i < 4; i++) {
        if (i != 0) {
            nhw += 64;
        }
        tn = nhw / param.div_ohow;
        hw = nhw % param.div_ohow;
        toh = hw / param.div_ow;
        tow = hw % param.div_ow;
        tih = toh * param.sh - param.ph;
        tiw = tow * param.sw - param.pw;
        g[i] = tn < param.n;
        h_start[i] = -tih;
        h_end[i] = param.ih - tih;
        w_start[i] = -tiw;
        w_end[i] = param.iw - tiw;
        // param's members have been converted to byte offset and int4 offset need to
        // div 2
        int src_offset = tn * param.ibs + tih * param.ihs +
                         ((int)(tiw * packed_channel + residue) >> 1);
        g_src_ptr[i * 2] = src + src_offset;
        g_src_ptr[i * 2 + 1] = g_src_ptr[i * 2];
    }

    const uint32_t section_section = (section >> 2);
    const uint32_t section_residue = (section & 3);
    const uint32_t section_factor = ((section & 15) >> 2);
    const uint32_t crosswise_offset =
            ((section_residue >> 1) << 4) +
            (((section_residue & 1) ^ (section_factor >> 1)) << 3);
    const uint32_t residue_offset = ((residue >> 5) ^ (section_factor & 1)) << 2;

    // next + 64 * BK / 8
    int32_t* write_src_s[2];
    write_src_s[0] =
            smem + section_section * BK / 2 + crosswise_offset + residue_offset;
    write_src_s[1] = write_src_s[0] + 32;

    int iter = (param.icfhfw >> 6);

    uint32_t tid31 = (tid & 31);
    uint32_t warp_idx = (tid >> 5);
    uint32_t warp_strided = (warp_idx << 1);
    uint32_t htid = (tid31 >> 4);
    const uint32_t flt_strided = bidy * BM / 8 + warp_strided;
    bool guard = flt_strided * 8 < param.oc && iter > htid;
    // icfhfw * 8/2 is a stride
    const int8_t* __restrict__ g_filter_ptr0 =
            filter + flt_strided * (param.icfhfw * 4) + (tid31 << 4);
    const int8_t* __restrict__ g_filter_ptr1 = g_filter_ptr0 + (param.icfhfw * 4);
    // next + BK * 8 / (INT32/INT4)
    uint32_t q = (tid31 >> 3);
    uint32_t r = (tid31 & 7);
    int32_t* write_flt_s = smem + BN * BK / 8 + warp_strided * BK + ((q & 1) << 6) +
                           ((q >> 1) << 5) + (r << 2);
    uint32_t quad_idx = (tid31 >> 2);
    uint32_t idx_in_quad = (tid & 3);
    uint32_t quad_factor = ((tid & 15) >> 2);
    uint32_t crosswise =
            ((idx_in_quad >> 1) << 4) + (((idx_in_quad & 1) ^ (quad_factor >> 1)) << 3);
    uint32_t warp_x = warp_idx;
    // low src
    int32_t* read_src_s_0 = smem + (warp_x * 8 * BK) + (quad_idx * BK / 2) + crosswise +
                            ((0 ^ (quad_factor & 1)) << 2);
    int32_t* read_src_s_1 = smem + (warp_x * 8 * BK) + (quad_idx * BK / 2) + crosswise +
                            ((1 ^ (quad_factor & 1)) << 2);
    // higt src
    int32_t* read_flt_s_0 = smem + BN * BK / 8 + (quad_idx * BK / 2) + crosswise +
                            ((0 ^ (quad_factor & 1)) << 2);
    int32_t* read_flt_s_1 = smem + BN * BK / 8 + (quad_idx * BK / 2) + crosswise +
                            ((1 ^ (quad_factor & 1)) << 2);

#pragma unroll
    for (int i = 0; i < reg_m; i++) {
#pragma unroll
        for (int j = 0; j < reg_n; j++) {
            reg_acc[i][j] = make_int2(0, 0);
        }
    }

    int32_t smem_switch = 5120;
    uint32_t offset[2] = {0, 2};  // high & low
    int src_step[2], x[2], y[2];

    for (int i = 0; i < 2; i++) {
        src_step[i] = conv2d_constant.c_offset[offset[i]];
        uint32_t spatial = *(reinterpret_cast<const uint32_t*>(
                &(conv2d_constant.c_offset[offset[i] + 1])));
        x[i] = (spatial & 0xff);
        y[i] = ((spatial >> 8) & 0xff);
        if (offset[i] < conv2d_constant.c_offset_param.max) {
            offset[i] += 4;
        } else {
            offset[i] += conv2d_constant.c_offset_param.rewind;
        }
    }

    bool guard0[2], guard1[2], guard2[2], guard3[2];
    guard0[0] = g[0] && x[0] >= h_start[0] && x[0] < h_end[0] && y[0] >= w_start[0] &&
                y[0] < w_end[0] && iter > 0;
    guard0[1] = g[0] && x[1] >= h_start[0] && x[1] < h_end[0] && y[1] >= w_start[0] &&
                y[1] < w_end[0] && iter > 1;
    guard1[0] = g[1] && x[0] >= h_start[1] && x[0] < h_end[1] && y[0] >= w_start[1] &&
                y[0] < w_end[1] && iter > 0;
    guard1[1] = g[1] && x[1] >= h_start[1] && x[1] < h_end[1] && y[1] >= w_start[1] &&
                y[1] < w_end[1] && iter > 1;
    guard2[0] = g[2] && x[0] >= h_start[2] && x[0] < h_end[2] && y[0] >= w_start[2] &&
                y[0] < w_end[2] && iter > 0;
    guard2[1] = g[2] && x[1] >= h_start[2] && x[1] < h_end[2] && y[1] >= w_start[2] &&
                y[1] < w_end[2] && iter > 1;
    guard3[0] = g[3] && x[0] >= h_start[3] && x[0] < h_end[3] && y[0] >= w_start[3] &&
                y[0] < w_end[3] && iter > 0;
    guard3[1] = g[3] && x[1] >= h_start[3] && x[1] < h_end[3] && y[1] >= w_start[3] &&
                y[1] < w_end[3] && iter > 1;
    g_src_ptr[0] += src_step[0];
    g_src_ptr[1] += src_step[1];
    g_src_ptr[2] += src_step[0];
    g_src_ptr[3] += src_step[1];
    g_src_ptr[4] += src_step[0];
    g_src_ptr[5] += src_step[1];
    g_src_ptr[6] += src_step[0];
    g_src_ptr[7] += src_step[1];

    if (guard0[0]) {
        reg_src_cache[0] = *(reinterpret_cast<const int4*>(g_src_ptr[0]));
    } else {
        reg_src_cache[0] = make_int4(
                pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                pk_src_zero_point);
    }
    if (guard0[1]) {
        reg_src_cache[1] = *(reinterpret_cast<const int4*>(g_src_ptr[1]));
    } else {
        reg_src_cache[1] = make_int4(
                pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                pk_src_zero_point);
    }
    if (guard1[0]) {
        reg_src_cache[2] = *(reinterpret_cast<const int4*>(g_src_ptr[2]));
    } else {
        reg_src_cache[2] = make_int4(
                pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                pk_src_zero_point);
    }
    if (guard1[1]) {
        reg_src_cache[3] = *(reinterpret_cast<const int4*>(g_src_ptr[3]));
    } else {
        reg_src_cache[3] = make_int4(
                pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                pk_src_zero_point);
    }
    if (guard2[0]) {
        reg_src_cache[4] = *(reinterpret_cast<const int4*>(g_src_ptr[4]));
    } else {
        reg_src_cache[4] = make_int4(
                pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                pk_src_zero_point);
    }
    if (guard2[1]) {
        reg_src_cache[5] = *(reinterpret_cast<const int4*>(g_src_ptr[5]));
    } else {
        reg_src_cache[5] = make_int4(
                pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                pk_src_zero_point);
    }
    if (guard3[0]) {
        reg_src_cache[6] = *(reinterpret_cast<const int4*>(g_src_ptr[6]));
    } else {
        reg_src_cache[6] = make_int4(
                pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                pk_src_zero_point);
    }
    if (guard3[1]) {
        reg_src_cache[7] = *(reinterpret_cast<const int4*>(g_src_ptr[7]));
    } else {
        reg_src_cache[7] = make_int4(
                pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                pk_src_zero_point);
    }

    if (guard) {
        reg_filter_cache[0] = *(reinterpret_cast<const int4*>(g_filter_ptr0));
        reg_filter_cache[1] = *(reinterpret_cast<const int4*>(g_filter_ptr1));
    } else {
        reg_filter_cache[0] = make_int4(0, 0, 0, 0);
        reg_filter_cache[1] = make_int4(0, 0, 0, 0);
    }

    *(reinterpret_cast<int4*>(write_src_s[0])) = reg_src_cache[0];
    *(reinterpret_cast<int4*>(write_src_s[1])) = reg_src_cache[1];
    *(reinterpret_cast<int4*>(write_src_s[0] + 8 * BK)) = reg_src_cache[2];
    *(reinterpret_cast<int4*>(write_src_s[1] + 8 * BK)) = reg_src_cache[3];
    *(reinterpret_cast<int4*>(write_src_s[0] + 16 * BK)) = reg_src_cache[4];
    *(reinterpret_cast<int4*>(write_src_s[1] + 16 * BK)) = reg_src_cache[5];
    *(reinterpret_cast<int4*>(write_src_s[0] + 24 * BK)) = reg_src_cache[6];
    *(reinterpret_cast<int4*>(write_src_s[1] + 24 * BK)) = reg_src_cache[7];
    *(reinterpret_cast<int4*>(write_flt_s)) = reg_filter_cache[0];
    *(reinterpret_cast<int4*>(write_flt_s + BK)) = reg_filter_cache[1];

    __syncthreads();

    iter -= 2;
    for (int i = 0; i < 2; i++) {
        src_step[i] = conv2d_constant.c_offset[offset[i]];
        uint32_t spatial = *(reinterpret_cast<const uint32_t*>(
                &(conv2d_constant.c_offset[offset[i] + 1])));
        x[i] = (spatial & 0xff);
        y[i] = ((spatial >> 8) & 0xff);
        if (offset[i] < conv2d_constant.c_offset_param.max) {
            offset[i] += 4;
        } else {
            offset[i] += conv2d_constant.c_offset_param.rewind;
        }
    }
    guard0[0] = g[0] && x[0] >= h_start[0] && x[0] < h_end[0] && y[0] >= w_start[0] &&
                y[0] < w_end[0];
    guard0[1] = g[0] && x[1] >= h_start[0] && x[1] < h_end[0] && y[1] >= w_start[0] &&
                y[1] < w_end[0];
    guard1[0] = g[1] && x[0] >= h_start[1] && x[0] < h_end[1] && y[0] >= w_start[1] &&
                y[0] < w_end[1];
    guard1[1] = g[1] && x[1] >= h_start[1] && x[1] < h_end[1] && y[1] >= w_start[1] &&
                y[1] < w_end[1];
    guard2[0] = g[2] && x[0] >= h_start[2] && x[0] < h_end[2] && y[0] >= w_start[2] &&
                y[0] < w_end[2];
    guard2[1] = g[2] && x[1] >= h_start[2] && x[1] < h_end[2] && y[1] >= w_start[2] &&
                y[1] < w_end[2];
    guard3[0] = g[3] && x[0] >= h_start[3] && x[0] < h_end[3] && y[0] >= w_start[3] &&
                y[0] < w_end[3];
    guard3[1] = g[3] && x[1] >= h_start[3] && x[1] < h_end[3] && y[1] >= w_start[3] &&
                y[1] < w_end[3];

    g_src_ptr[0] += src_step[0];
    g_src_ptr[1] += src_step[1];
    g_src_ptr[2] += src_step[0];
    g_src_ptr[3] += src_step[1];
    g_src_ptr[4] += src_step[0];
    g_src_ptr[5] += src_step[1];
    g_src_ptr[6] += src_step[0];
    g_src_ptr[7] += src_step[1];
    g_filter_ptr0 += 8 * 64;
    g_filter_ptr1 += 8 * 64;

    write_src_s[0] += smem_switch;
    write_src_s[1] += smem_switch;
    write_flt_s += smem_switch;

    for (; iter >= 2; iter -= 2) {
        if (guard0[0]) {
            reg_src_cache[0] = *(reinterpret_cast<const int4*>(g_src_ptr[0]));
        } else {
            reg_src_cache[0] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard0[1]) {
            reg_src_cache[1] = *(reinterpret_cast<const int4*>(g_src_ptr[1]));
        } else {
            reg_src_cache[1] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard1[0]) {
            reg_src_cache[2] = *(reinterpret_cast<const int4*>(g_src_ptr[2]));
        } else {
            reg_src_cache[2] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard1[1]) {
            reg_src_cache[3] = *(reinterpret_cast<const int4*>(g_src_ptr[3]));
        } else {
            reg_src_cache[3] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard2[0]) {
            reg_src_cache[4] = *(reinterpret_cast<const int4*>(g_src_ptr[4]));
        } else {
            reg_src_cache[4] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard2[1]) {
            reg_src_cache[5] = *(reinterpret_cast<const int4*>(g_src_ptr[5]));
        } else {
            reg_src_cache[5] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard3[0]) {
            reg_src_cache[6] = *(reinterpret_cast<const int4*>(g_src_ptr[6]));
        } else {
            reg_src_cache[6] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard3[1]) {
            reg_src_cache[7] = *(reinterpret_cast<const int4*>(g_src_ptr[7]));
        } else {
            reg_src_cache[7] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }

        if (guard) {
            reg_filter_cache[0] = *(reinterpret_cast<const int4*>(g_filter_ptr0));
            reg_filter_cache[1] = *(reinterpret_cast<const int4*>(g_filter_ptr1));
        } else {
            reg_filter_cache[0] = make_int4(0, 0, 0, 0);
            reg_filter_cache[1] = make_int4(0, 0, 0, 0);
        }

#pragma unroll  // low
        for (int i = 0; i < reg_nd4; ++i) {
            int x, y, z, w;
            unsigned addr = get_smem_pointer(read_src_s_0 + i * 4 * BK);  // BK*32/8
            asm volatile(
                    "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, %3}, "
                    "[%4];"
                    : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                    : "r"(addr));
            reg_src[0][i] = make_int4(x, y, z, w);
        }

#pragma unroll
        for (int j = 0; j < reg_md4; ++j) {
            int x, y, z, w;
            unsigned addr = get_smem_pointer(read_flt_s_0 + 4 * j * BK);
            asm volatile(
                    "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, %3}, "
                    "[%4];"
                    : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                    : "r"(addr));
            reg_flt[0][j] = make_int4(x, y, z, w);
        }

        smem_switch = -smem_switch;
#pragma unroll
        for (int k_inner = 0; k_inner < BKd32; k_inner++) {
            int comp = (k_inner & 0x1);
            int load = 1 - comp;
            if (k_inner < BKd32 - 1) {
                int32_t* read_src_s = (k_inner & 1) ? read_src_s_0 : read_src_s_1;
                int32_t* read_flt_s = (k_inner & 1) ? read_flt_s_0 : read_flt_s_1;
                read_src_s += 32 * ((k_inner + 1) >> 1);
                read_flt_s += 32 * ((k_inner + 1) >> 1);

#pragma unroll  // low
                for (int i = 0; i < reg_nd4; ++i) {
                    int x, y, z, w;
                    unsigned addr =
                            get_smem_pointer(read_src_s + i * 4 * BK);  // BK*32/8
                    asm volatile(
                            "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, "
                            "%3}, "
                            "[%4];"
                            : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                            : "r"(addr));
                    reg_src[load][i] = make_int4(x, y, z, w);
                }
#pragma unroll
                for (int j = 0; j < reg_md4; ++j) {
                    int x, y, z, w;
                    unsigned addr = get_smem_pointer(read_flt_s + 4 * j * BK);
                    asm volatile(
                            "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, "
                            "%3}, "
                            "[%4];"
                            : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                            : "r"(addr));
                    reg_flt[load][j] = make_int4(x, y, z, w);
                }
            }

            int* A = reinterpret_cast<int*>(&reg_flt[comp][0]);
            int* B = reinterpret_cast<int*>(&reg_src[comp][0]);
#pragma unroll
            for (int x = 0; x < reg_n; x++) {
#pragma unroll
                for (int y = 0; y < reg_m; y++) {
                    int* D = reinterpret_cast<int*>(&reg_acc[y][x]);
                    int* C = reinterpret_cast<int*>(&reg_acc[y][x]);
                    asm volatile(
                            "mma.sync.aligned.m8n8k32.row.col.satfinite.s32.u4.s4."
                            "s32 "
                            "{%0,%1}, {%2}, {%3}, "
                            "{%4,%5};\n"
                            : "=r"(D[0]), "=r"(D[1])
                            : "r"(B[y]), "r"(A[x]), "r"(C[0]), "r"(C[1]));
                }
            }
        }

        *(reinterpret_cast<int4*>(write_src_s[0])) = reg_src_cache[0];
        *(reinterpret_cast<int4*>(write_src_s[1])) = reg_src_cache[1];
        *(reinterpret_cast<int4*>(write_src_s[0] + 8 * BK)) = reg_src_cache[2];
        *(reinterpret_cast<int4*>(write_src_s[1] + 8 * BK)) = reg_src_cache[3];
        *(reinterpret_cast<int4*>(write_src_s[0] + 16 * BK)) = reg_src_cache[4];
        *(reinterpret_cast<int4*>(write_src_s[1] + 16 * BK)) = reg_src_cache[5];
        *(reinterpret_cast<int4*>(write_src_s[0] + 24 * BK)) = reg_src_cache[6];
        *(reinterpret_cast<int4*>(write_src_s[1] + 24 * BK)) = reg_src_cache[7];
        *(reinterpret_cast<int4*>(write_flt_s)) = reg_filter_cache[0];
        *(reinterpret_cast<int4*>(write_flt_s + BK)) = reg_filter_cache[1];

        write_src_s[0] += smem_switch;
        write_src_s[1] += smem_switch;
        write_flt_s += smem_switch;
        read_src_s_0 -= smem_switch;
        read_src_s_1 -= smem_switch;
        read_flt_s_0 -= smem_switch;
        read_flt_s_1 -= smem_switch;
        __syncthreads();
        int src_step[2];
        for (int i = 0; i < 2; i++) {
            src_step[i] = conv2d_constant.c_offset[offset[i]];
            uint32_t spatial = *(reinterpret_cast<const uint32_t*>(
                    &(conv2d_constant.c_offset[offset[i] + 1])));
            x[i] = (spatial & 0xff);
            y[i] = ((spatial >> 8) & 0xff);
            if (offset[i] < conv2d_constant.c_offset_param.max) {
                offset[i] += 4;
            } else {
                offset[i] += conv2d_constant.c_offset_param.rewind;
            }
        }
        guard0[0] = g[0] && x[0] >= h_start[0] && x[0] < h_end[0] &&
                    y[0] >= w_start[0] && y[0] < w_end[0];
        guard0[1] = g[0] && x[1] >= h_start[0] && x[1] < h_end[0] &&
                    y[1] >= w_start[0] && y[1] < w_end[0];
        guard1[0] = g[1] && x[0] >= h_start[1] && x[0] < h_end[1] &&
                    y[0] >= w_start[1] && y[0] < w_end[1];
        guard1[1] = g[1] && x[1] >= h_start[1] && x[1] < h_end[1] &&
                    y[1] >= w_start[1] && y[1] < w_end[1];
        guard2[0] = g[2] && x[0] >= h_start[2] && x[0] < h_end[2] &&
                    y[0] >= w_start[2] && y[0] < w_end[2];
        guard2[1] = g[2] && x[1] >= h_start[2] && x[1] < h_end[2] &&
                    y[1] >= w_start[2] && y[1] < w_end[2];
        guard3[0] = g[3] && x[0] >= h_start[3] && x[0] < h_end[3] &&
                    y[0] >= w_start[3] && y[0] < w_end[3];
        guard3[1] = g[3] && x[1] >= h_start[3] && x[1] < h_end[3] &&
                    y[1] >= w_start[3] && y[1] < w_end[3];
        g_src_ptr[0] += src_step[0];
        g_src_ptr[1] += src_step[1];
        g_src_ptr[2] += src_step[0];
        g_src_ptr[3] += src_step[1];
        g_src_ptr[4] += src_step[0];
        g_src_ptr[5] += src_step[1];
        g_src_ptr[6] += src_step[0];
        g_src_ptr[7] += src_step[1];
        g_filter_ptr0 += 8 * 64;
        g_filter_ptr1 += 8 * 64;
    }

    if (iter > 0) {
        if (guard0[0]) {
            reg_src_cache[0] = *(reinterpret_cast<const int4*>(g_src_ptr[0]));
        } else {
            reg_src_cache[0] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard0[1] && iter > 1) {
            reg_src_cache[1] = *(reinterpret_cast<const int4*>(g_src_ptr[1]));
        } else {
            reg_src_cache[1] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard1[0]) {
            reg_src_cache[2] = *(reinterpret_cast<const int4*>(g_src_ptr[2]));
        } else {
            reg_src_cache[2] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard1[1] && iter > 1) {
            reg_src_cache[3] = *(reinterpret_cast<const int4*>(g_src_ptr[3]));
        } else {
            reg_src_cache[3] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard2[0]) {
            reg_src_cache[4] = *(reinterpret_cast<const int4*>(g_src_ptr[4]));
        } else {
            reg_src_cache[4] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard2[1] && iter > 1) {
            reg_src_cache[5] = *(reinterpret_cast<const int4*>(g_src_ptr[5]));
        } else {
            reg_src_cache[5] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard3[0]) {
            reg_src_cache[6] = *(reinterpret_cast<const int4*>(g_src_ptr[6]));
        } else {
            reg_src_cache[6] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }
        if (guard3[1] && iter > 1) {
            reg_src_cache[7] = *(reinterpret_cast<const int4*>(g_src_ptr[7]));
        } else {
            reg_src_cache[7] = make_int4(
                    pk_src_zero_point, pk_src_zero_point, pk_src_zero_point,
                    pk_src_zero_point);
        }

        if (guard && iter > htid) {
            reg_filter_cache[0] = *(reinterpret_cast<const int4*>(g_filter_ptr0));
            reg_filter_cache[1] = *(reinterpret_cast<const int4*>(g_filter_ptr1));
        } else {
            reg_filter_cache[0] = make_int4(0, 0, 0, 0);
            reg_filter_cache[1] = make_int4(0, 0, 0, 0);
        }

#pragma unroll  // low
        for (int i = 0; i < reg_nd4; ++i) {
            int x, y, z, w;
            unsigned addr = get_smem_pointer(read_src_s_0 + i * 4 * BK);  // BK*32/8
            asm volatile(
                    "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, %3}, "
                    "[%4];"
                    : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                    : "r"(addr));
            reg_src[0][i] = make_int4(x, y, z, w);
        }
#pragma unroll
        for (int j = 0; j < reg_md4; ++j) {
            int x, y, z, w;
            unsigned addr = get_smem_pointer(read_flt_s_0 + 4 * j * BK);
            asm volatile(
                    "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, %3}, "
                    "[%4];"
                    : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                    : "r"(addr));
            reg_flt[0][j] = make_int4(x, y, z, w);
        }

        smem_switch = -smem_switch;
#pragma unroll
        for (int k_inner = 0; k_inner < BKd32; k_inner++) {
            int comp = (k_inner & 0x1);
            int load = 1 - comp;
            if (k_inner < BKd32 - 1) {
                int32_t* read_src_s = (k_inner & 1) ? read_src_s_0 : read_src_s_1;
                int32_t* read_flt_s = (k_inner & 1) ? read_flt_s_0 : read_flt_s_1;
                read_src_s += 32 * ((k_inner + 1) >> 1);
                read_flt_s += 32 * ((k_inner + 1) >> 1);

#pragma unroll  // low
                for (int i = 0; i < reg_nd4; ++i) {
                    int x, y, z, w;
                    unsigned addr =
                            get_smem_pointer(read_src_s + i * 4 * BK);  // BK*32/8
                    asm volatile(
                            "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, "
                            "%3}, "
                            "[%4];"
                            : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                            : "r"(addr));
                    reg_src[load][i] = make_int4(x, y, z, w);
                }
#pragma unroll
                for (int j = 0; j < reg_md4; ++j) {
                    int x, y, z, w;
                    unsigned addr = get_smem_pointer(read_flt_s + 4 * j * BK);
                    asm volatile(
                            "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, "
                            "%3}, "
                            "[%4];"
                            : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                            : "r"(addr));
                    reg_flt[load][j] = make_int4(x, y, z, w);
                }
            }

            int* A = reinterpret_cast<int*>(&reg_flt[comp][0]);
            int* B = reinterpret_cast<int*>(&reg_src[comp][0]);
#pragma unroll
            for (int x = 0; x < reg_n; x++) {
#pragma unroll
                for (int y = 0; y < reg_m; y++) {
                    int* D = reinterpret_cast<int*>(&reg_acc[y][x]);
                    int* C = reinterpret_cast<int*>(&reg_acc[y][x]);
                    asm volatile(
                            "mma.sync.aligned.m8n8k32.row.col.satfinite.s32.u4.s4."
                            "s32 "
                            "{%0,%1}, {%2}, {%3}, "
                            "{%4,%5};\n"
                            : "=r"(D[0]), "=r"(D[1])
                            : "r"(B[y]), "r"(A[x]), "r"(C[0]), "r"(C[1]));
                }
            }
        }

        *(reinterpret_cast<int4*>(write_src_s[0])) = reg_src_cache[0];
        *(reinterpret_cast<int4*>(write_src_s[1])) = reg_src_cache[1];
        *(reinterpret_cast<int4*>(write_src_s[0] + 8 * BK)) = reg_src_cache[2];
        *(reinterpret_cast<int4*>(write_src_s[1] + 8 * BK)) = reg_src_cache[3];
        *(reinterpret_cast<int4*>(write_src_s[0] + 16 * BK)) = reg_src_cache[4];
        *(reinterpret_cast<int4*>(write_src_s[1] + 16 * BK)) = reg_src_cache[5];
        *(reinterpret_cast<int4*>(write_src_s[0] + 24 * BK)) = reg_src_cache[6];
        *(reinterpret_cast<int4*>(write_src_s[1] + 24 * BK)) = reg_src_cache[7];
        *(reinterpret_cast<int4*>(write_flt_s)) = reg_filter_cache[0];
        *(reinterpret_cast<int4*>(write_flt_s + BK)) = reg_filter_cache[1];

        read_src_s_0 -= smem_switch;
        read_src_s_1 -= smem_switch;
        read_flt_s_0 -= smem_switch;
        read_flt_s_1 -= smem_switch;

        __syncthreads();
    }

    guard = iter < 0;
#pragma unroll  // low
    for (int i = 0; i < reg_nd4; ++i) {
        int x, y, z, w;
        unsigned addr = get_smem_pointer(read_src_s_0 + i * 4 * BK);  // BK*32/8
        asm volatile(
                "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, "
                "%3}, "
                "[%4];"
                : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                : "r"(addr));
        reg_src[0][i] = make_int4(x, y, z, w);
    }
#pragma unroll
    for (int j = 0; j < reg_md4; ++j) {
        int x, y, z, w;
        unsigned addr = get_smem_pointer(read_flt_s_0 + 4 * j * BK);
        asm volatile(
                "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, "
                "%3}, "
                "[%4];"
                : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                : "r"(addr));
        reg_flt[0][j] = make_int4(x, y, z, w);
    }

// compute
#pragma unroll
    for (int k_inner = 0; k_inner < BKd32; k_inner++) {
        int comp = (k_inner & 0x1);
        int load = 1 - comp;
        if (k_inner < BKd32 - 1 && !(k_inner == 1 && guard)) {
            int32_t* read_src_s = (k_inner & 1) ? read_src_s_0 : read_src_s_1;
            int32_t* read_flt_s = (k_inner & 1) ? read_flt_s_0 : read_flt_s_1;
            read_src_s += 32 * ((k_inner + 1) >> 1);
            read_flt_s += 32 * ((k_inner + 1) >> 1);

#pragma unroll  // low
            for (int i = 0; i < reg_nd4; ++i) {
                int x, y, z, w;
                unsigned addr = get_smem_pointer(read_src_s + i * 4 * BK);  // BK*32/8
                asm volatile(
                        "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, "
                        "%3}, "
                        "[%4];"
                        : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                        : "r"(addr));
                reg_src[load][i] = make_int4(x, y, z, w);
            }
#pragma unroll
            for (int j = 0; j < reg_md4; ++j) {
                int x, y, z, w;
                unsigned addr = get_smem_pointer(read_flt_s + 4 * j * BK);
                asm volatile(
                        "ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, "
                        "%3}, "
                        "[%4];"
                        : "=r"(x), "=r"(y), "=r"(z), "=r"(w)
                        : "r"(addr));
                reg_flt[load][j] = make_int4(x, y, z, w);
            }
        }

        int* A = reinterpret_cast<int*>(&reg_flt[comp][0]);
        int* B = reinterpret_cast<int*>(&reg_src[comp][0]);
#pragma unroll
        for (int x = 0; x < reg_n; x++) {
#pragma unroll
            for (int y = 0; y < reg_m; y++) {
                int* D = reinterpret_cast<int*>(&reg_acc[y][x]);
                int* C = reinterpret_cast<int*>(&reg_acc[y][x]);
                asm volatile(
                        "mma.sync.aligned.m8n8k32.row.col.satfinite.s32.u4.s4."
                        "s32 "
                        "{%0,%1}, {%2}, {%3}, "
                        "{%4,%5};\n"
                        : "=r"(D[0]), "=r"(D[1])
                        : "r"(B[y]), "r"(A[x]), "r"(C[0]), "r"(C[1]));
            }
        }
        if (k_inner == 1 && guard) {
            break;
        }
    }

    __syncthreads();

    /// output
    bool stg_guard[4];
    section = tid31 >> 2;
    size_t nhw_post0 = bidx * BN + warp_x * 64 + section;
    size_t nhw_post1 = nhw_post0 + 8;
    size_t nhw_post2 = nhw_post0 + 16;
    size_t nhw_post3 = nhw_post0 + 24;

    size_t stg_oc = bidy * BM;
    size_t oc = bidy * BM + 16 * idx_in_quad;
    const float* bias_ptr = bias + oc;

    int4 load_bias0 = make_int4(0, 0, 0, 0);
    int4 load_bias1 = make_int4(0, 0, 0, 0);
    int4 load_bias2 = make_int4(0, 0, 0, 0);
    int4 load_bias3 = make_int4(0, 0, 0, 0);
    if (oc < param.oc) {
        load_bias0 = *(reinterpret_cast<const int4*>(bias_ptr));
        load_bias1 = *(reinterpret_cast<const int4*>(bias_ptr + 4));
        load_bias2 = *(reinterpret_cast<const int4*>(bias_ptr + 8));
        load_bias3 = *(reinterpret_cast<const int4*>(bias_ptr + 12));
        mul_v4(load_bias0, load_bias0, beta);
        mul_v4(load_bias1, load_bias1, beta);
        mul_v4(load_bias2, load_bias2, beta);
        mul_v4(load_bias3, load_bias3, beta);
    }

    int8_t* __restrict__ g_dst_ptr =
            dst + (bidy * (BM >> 6)) * param.ocs + (idx_in_quad << 3);
    int8_t** stg_ptr = ((int8_t**)&reg_filter_cache);

#pragma unroll
    for (int y = 0; y < reg_m; y += 4) {
        I2F_4x8(reg_acc, y, 0);
        FMA_4x8(reg_acc, y, 0, alpha, load_bias0, load_bias1, load_bias2, load_bias3);
        PACK_F2I_WITH_RELU_4x8(reg_acc, y, 0, relu, dst_zero_point);
        STG_4x1(stg_ptr, reg_acc, y, 0);

        nhw_post0 += 32;
        nhw_post1 += 32;
        nhw_post2 += 32;
        nhw_post3 += 32;
    }
#endif
}
}  // namespace

namespace megdnn {
namespace cuda {
namespace ptx {
void run_ampere_conv_bias_uint4_int4_imma8832_ldg16_256x64_relu(
        const dim3 grid, const dim3 block, cudaStream_t stream, void** params) {
#ifdef SM80_SUPPORTED
    ampere_conv_bias_uint4_int4_imma8832_ldg16_256x64_relu<<<grid, block, 0, stream>>>(
            *((int8_t**)params[0]), *((int8_t**)params[1]), *((float**)params[2]),
            *((int8_t**)params[3]), *((float*)params[4]), *((float*)params[5]),
            *((uint32_t*)params[6]), *((float*)params[7]), *((uint32_t*)params[8]),
            *((Conv2dInt4Param*)params[9]), *((Conv2dConstantOffset*)params[10]));
#endif
}
}  // namespace ptx
}  // namespace cuda
}  // namespace megdnn

// vim: syntax=cpp.doxygen
