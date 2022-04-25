#pragma once

#include "src/cuda/utils.cuh"

#include <cuda_runtime_api.h>
#include <stdint.h>

namespace megdnn {
namespace cuda {
namespace cumprod {

//! compute conventional sum of elements
template <typename T>
struct ProdOp {
    const T* data;
    typedef ProdOp ContigOp;

    ProdOp(const T* d) : data(d) {}

    __host__ __device__ static T init() { return T(1); }
    __device__ static T apply(T lhs, T rhs) { return lhs * rhs; }
    __device__ T visit(uint32_t idx) const { return data[idx]; }

    static ProdOp make_contig(const T* data) { return ProdOp(data); }
};

/*!
 * \brief cumprod kernel launcher; defined in kern_impl.cuinl
 * \tparam T output data type
 * \tparam Op reduction operator class, which must provide following interface:
 *      typdef ContigOp
 *      static T init(): the identity element
 *      static T apply(T lhs, T rhs): the reduction operation
 *      T visit(uint32_t idx) const: access input
 *      static ContigOp make_contig(const T *data): make an Oo to continue
 *          reduction on temp buffer
 *
 * Note that Op::init() must be accessible from both host and device.
 *
 * In exclusive mode, Op::init() would be filled to the boundary
 *
 * The buffer in *op* and *dst* should not have identical memory addresses.
 */
template <typename T, typename Op, bool exclusive, bool reverse>
void run_kern(
        T* dst, void* workspace, uint32_t workspace_size, uint32_t A, uint32_t B,
        uint32_t C, const Op& op, cudaStream_t stream);

/*!
 * \brief get required workspace size for cumprod, in bytes
 * \param item_size size of item; i.e. sizeof(T) in run_kern
 *
 * Note: cuda device must be set to the computing device before calling this
 * function.
 */
uint32_t get_workspace_in_bytes(uint32_t A, uint32_t B, uint32_t C, uint32_t item_size);

}  // namespace cumprod
}  // namespace cuda
}  // namespace megdnn

// vim: ft=cpp syntax=cpp.doxygen
