/**
 * \file dnn/src/fallback/elemwise_helper/op_binary.h
 */

#pragma once

#include "src/fallback/elemwise_helper/kimpl/add.h"
#include "src/fallback/elemwise_helper/kimpl/fuse_add_h_swish.h"
#include "src/fallback/elemwise_helper/kimpl/fuse_add_relu.h"
#include "src/fallback/elemwise_helper/kimpl/fuse_add_sigmoid.h"
#include "src/fallback/elemwise_helper/kimpl/fuse_add_tanh.h"
#include "src/fallback/elemwise_helper/kimpl/max.h"
#include "src/fallback/elemwise_helper/kimpl/min.h"
#include "src/fallback/elemwise_helper/kimpl/mul.h"
#include "src/fallback/elemwise_helper/kimpl/pow.h"
#include "src/fallback/elemwise_helper/kimpl/sub.h"
#include "src/fallback/elemwise_helper/kimpl/true_div.h"

//////////////////// quantization //////////////////////////////
namespace megdnn {
namespace fallback {
#define cb(op)                                                               \
    template <>                                                              \
    struct op<dt_qint8, dt_qint8>                                            \
            : BinaryQuantizationOp<dt_qint8, dt_qint8, op<float, float>> {   \
        using BinaryQuantizationOp<                                          \
                dt_qint8, dt_qint8, op<float, float>>::BinaryQuantizationOp; \
    };

cb(TrueDivOp);
cb(FuseAddSigmoidOp);
cb(FuseAddTanhOp);
cb(FuseAddHSwishOp);

#undef cb
}  // namespace fallback
}  // namespace megdnn

// vim: syntax=cpp.doxygen
