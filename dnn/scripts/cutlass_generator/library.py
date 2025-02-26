#
# \file generator.py
#
# \brief Generates the CUTLASS Library's instances
#

import enum
import re

###################################################################################################


# The following block implements enum.auto() for Python 3.5 variants that don't include it such
# as the default 3.5.2 on Ubuntu 16.04.
#
# https://codereview.stackexchange.com/questions/177309/reimplementing-pythons-enum-auto-for-compatibility

try:
    from enum import auto as enum_auto
except ImportError:
    __cutlass_library_auto_enum = 0

    def enum_auto() -> int:
        global __cutlass_library_auto_enum
        i = __cutlass_library_auto_enum
        __cutlass_library_auto_enum += 1
        return i


###################################################################################################

#
class GeneratorTarget(enum.Enum):
    Library = enum_auto()


#
GeneratorTargetNames = {GeneratorTarget.Library: "library"}
#

###################################################################################################

#
class DataType(enum.Enum):
    b1 = enum_auto()
    u4 = enum_auto()
    u8 = enum_auto()
    u16 = enum_auto()
    u32 = enum_auto()
    u64 = enum_auto()
    s4 = enum_auto()
    s8 = enum_auto()
    s16 = enum_auto()
    s32 = enum_auto()
    s64 = enum_auto()
    f16 = enum_auto()
    bf16 = enum_auto()
    f32 = enum_auto()
    tf32 = enum_auto()
    f64 = enum_auto()
    cf16 = enum_auto()
    cbf16 = enum_auto()
    cf32 = enum_auto()
    ctf32 = enum_auto()
    cf64 = enum_auto()
    cs4 = enum_auto()
    cs8 = enum_auto()
    cs16 = enum_auto()
    cs32 = enum_auto()
    cs64 = enum_auto()
    cu4 = enum_auto()
    cu8 = enum_auto()
    cu16 = enum_auto()
    cu32 = enum_auto()
    cu64 = enum_auto()
    invalid = enum_auto()


#
ShortDataTypeNames = {
    DataType.s32: "i",
    DataType.f16: "h",
    DataType.f32: "s",
    DataType.f64: "d",
    DataType.cf32: "c",
    DataType.cf64: "z",
}

#
DataTypeNames = {
    DataType.b1: "b1",
    DataType.u4: "u4",
    DataType.u8: "u8",
    DataType.u16: "u16",
    DataType.u32: "u32",
    DataType.u64: "u64",
    DataType.s4: "s4",
    DataType.s8: "s8",
    DataType.s16: "s16",
    DataType.s32: "s32",
    DataType.s64: "s64",
    DataType.f16: "f16",
    DataType.bf16: "bf16",
    DataType.f32: "f32",
    DataType.tf32: "tf32",
    DataType.f64: "f64",
    DataType.cf16: "cf16",
    DataType.cbf16: "cbf16",
    DataType.cf32: "cf32",
    DataType.ctf32: "ctf32",
    DataType.cf64: "cf64",
    DataType.cu4: "cu4",
    DataType.cu8: "cu8",
    DataType.cu16: "cu16",
    DataType.cu32: "cu32",
    DataType.cu64: "cu64",
    DataType.cs4: "cs4",
    DataType.cs8: "cs8",
    DataType.cs16: "cs16",
    DataType.cs32: "cs32",
    DataType.cs64: "cs64",
}

DataTypeTag = {
    DataType.b1: "cutlass::uint1b_t",
    DataType.u4: "cutlass::uint4b_t",
    DataType.u8: "uint8_t",
    DataType.u16: "uint16_t",
    DataType.u32: "uint32_t",
    DataType.u64: "uint64_t",
    DataType.s4: "cutlass::int4b_t",
    DataType.s8: "int8_t",
    DataType.s16: "int16_t",
    DataType.s32: "int32_t",
    DataType.s64: "int64_t",
    DataType.f16: "cutlass::half_t",
    DataType.bf16: "cutlass::bfloat16_t",
    DataType.f32: "float",
    DataType.tf32: "cutlass::tfloat32_t",
    DataType.f64: "double",
    DataType.cf16: "cutlass::complex<cutlass::half_t>",
    DataType.cbf16: "cutlass::complex<cutlass::bfloat16_t>",
    DataType.cf32: "cutlass::complex<float>",
    DataType.ctf32: "cutlass::complex<cutlass::tfloat32_t>",
    DataType.cf64: "cutlass::complex<double>",
    DataType.cu4: "cutlass::complex<cutlass::uint4b_t>",
    DataType.cu8: "cutlass::complex<cutlass::uint8_t>",
    DataType.cu16: "cutlass::complex<cutlass::uint16_t>",
    DataType.cu32: "cutlass::complex<cutlass::uint32_t>",
    DataType.cu64: "cutlass::complex<cutlass::uint64_t>",
    DataType.cs4: "cutlass::complex<cutlass::int4b_t>",
    DataType.cs8: "cutlass::complex<cutlass::int8_t>",
    DataType.cs16: "cutlass::complex<cutlass::int16_t>",
    DataType.cs32: "cutlass::complex<cutlass::int32_t>",
    DataType.cs64: "cutlass::complex<cutlass::int64_t>",
}

DataTypeSize = {
    DataType.b1: 1,
    DataType.u4: 4,
    DataType.u8: 4,
    DataType.u16: 16,
    DataType.u32: 32,
    DataType.u64: 64,
    DataType.s4: 4,
    DataType.s8: 8,
    DataType.s16: 16,
    DataType.s32: 32,
    DataType.s64: 64,
    DataType.f16: 16,
    DataType.bf16: 16,
    DataType.f32: 32,
    DataType.tf32: 32,
    DataType.f64: 64,
    DataType.cf16: 32,
    DataType.cbf16: 32,
    DataType.cf32: 64,
    DataType.ctf32: 32,
    DataType.cf64: 128,
    DataType.cu4: 8,
    DataType.cu8: 16,
    DataType.cu16: 32,
    DataType.cu32: 64,
    DataType.cu64: 128,
    DataType.cs4: 8,
    DataType.cs8: 16,
    DataType.cs16: 32,
    DataType.cs32: 64,
    DataType.cs64: 128,
}

###################################################################################################

#
class ComplexTransform(enum.Enum):
    none = enum_auto()
    conj = enum_auto()


#
ComplexTransformTag = {
    ComplexTransform.none: "cutlass::ComplexTransform::kNone",
    ComplexTransform.conj: "cutlass::ComplexTransform::kConjugate",
}

#
RealComplexBijection = [
    (DataType.f16, DataType.cf16),
    (DataType.f32, DataType.cf32),
    (DataType.f64, DataType.cf64),
]

#
def is_complex(data_type):
    for r, c in RealComplexBijection:
        if data_type == c:
            return True
    return False


#
def get_complex_from_real(real_type):
    for r, c in RealComplexBijection:
        if real_type == r:
            return c
    return DataType.invalid


#
def get_real_from_complex(complex_type):
    for r, c in RealComplexBijection:
        if complex_type == c:
            return r
    return DataType.invalid


#
class ComplexMultiplyOp(enum.Enum):
    multiply_add = enum_auto()
    gaussian = enum_auto()


###################################################################################################

#
class MathOperation(enum.Enum):
    multiply_add = enum_auto()
    multiply_add_saturate = enum_auto()
    xor_popc = enum_auto()
    multiply_add_fast_bf16 = enum_auto()
    multiply_add_fast_f16 = enum_auto()
    multiply_add_complex = enum_auto()
    multiply_add_complex_gaussian = enum_auto()


#
MathOperationTag = {
    MathOperation.multiply_add: "cutlass::arch::OpMultiplyAdd",
    MathOperation.multiply_add_saturate: "cutlass::arch::OpMultiplyAddSaturate",
    MathOperation.xor_popc: "cutlass::arch::OpXorPopc",
    MathOperation.multiply_add_fast_bf16: "cutlass::arch::OpMultiplyAddFastBF16",
    MathOperation.multiply_add_fast_f16: "cutlass::arch::OpMultiplyAddFastF16",
    MathOperation.multiply_add_complex: "cutlass::arch::OpMultiplyAddComplex",
    MathOperation.multiply_add_complex_gaussian: "cutlass::arch::OpMultiplyAddGaussianComplex",
}

###################################################################################################

#
class LayoutType(enum.Enum):
    ColumnMajor = enum_auto()
    RowMajor = enum_auto()
    ColumnMajorInterleaved2 = enum_auto()
    RowMajorInterleaved2 = enum_auto()
    ColumnMajorInterleaved32 = enum_auto()
    RowMajorInterleaved32 = enum_auto()
    ColumnMajorInterleaved64 = enum_auto()
    RowMajorInterleaved64 = enum_auto()
    TensorNHWC = enum_auto()
    TensorNDHWC = enum_auto()
    TensorNCHW = enum_auto()
    TensorNGHWC = enum_auto()
    TensorNC4HW4 = enum_auto()
    TensorC4RSK4 = enum_auto()
    TensorNC8HW8 = enum_auto()
    TensorNC16HW16 = enum_auto()
    TensorNC32HW32 = enum_auto()
    TensorNC64HW64 = enum_auto()
    TensorC32RSK32 = enum_auto()
    TensorC64RSK64 = enum_auto()
    TensorK4RSC4 = enum_auto()
    TensorCK4RS4 = enum_auto()
    TensorCK8RS8 = enum_auto()
    TensorCK16RS16 = enum_auto()


#
LayoutTag = {
    LayoutType.ColumnMajor: "cutlass::layout::ColumnMajor",
    LayoutType.RowMajor: "cutlass::layout::RowMajor",
    LayoutType.ColumnMajorInterleaved2: "cutlass::layout::ColumnMajorInterleaved<2>",
    LayoutType.RowMajorInterleaved2: "cutlass::layout::RowMajorInterleaved<2>",
    LayoutType.ColumnMajorInterleaved32: "cutlass::layout::ColumnMajorInterleaved<32>",
    LayoutType.RowMajorInterleaved32: "cutlass::layout::RowMajorInterleaved<32>",
    LayoutType.ColumnMajorInterleaved64: "cutlass::layout::ColumnMajorInterleaved<64>",
    LayoutType.RowMajorInterleaved64: "cutlass::layout::RowMajorInterleaved<64>",
    LayoutType.TensorNHWC: "cutlass::layout::TensorNHWC",
    LayoutType.TensorNDHWC: "cutlass::layout::TensorNDHWC",
    LayoutType.TensorNCHW: "cutlass::layout::TensorNCHW",
    LayoutType.TensorNGHWC: "cutlass::layout::TensorNGHWC",
    LayoutType.TensorNC4HW4: "cutlass::layout::TensorNCxHWx<4>",
    LayoutType.TensorC4RSK4: "cutlass::layout::TensorCxRSKx<4>",
    LayoutType.TensorNC8HW8: "cutlass::layout::TensorNCxHWx<8>",
    LayoutType.TensorNC16HW16: "cutlass::layout::TensorNCxHWx<16>",
    LayoutType.TensorNC32HW32: "cutlass::layout::TensorNCxHWx<32>",
    LayoutType.TensorC32RSK32: "cutlass::layout::TensorCxRSKx<32>",
    LayoutType.TensorNC64HW64: "cutlass::layout::TensorNCxHWx<64>",
    LayoutType.TensorC64RSK64: "cutlass::layout::TensorCxRSKx<64>",
    LayoutType.TensorK4RSC4: "cutlass::layout::TensorKxRSCx<4>",
    LayoutType.TensorCK4RS4: "cutlass::layout::TensorCKxRSx<4>",
    LayoutType.TensorCK8RS8: "cutlass::layout::TensorCKxRSx<8>",
    LayoutType.TensorCK16RS16: "cutlass::layout::TensorCKxRSx<16>",
}

#
TransposedLayout = {
    LayoutType.ColumnMajor: LayoutType.RowMajor,
    LayoutType.RowMajor: LayoutType.ColumnMajor,
    LayoutType.ColumnMajorInterleaved2: LayoutType.RowMajorInterleaved2,
    LayoutType.RowMajorInterleaved2: LayoutType.ColumnMajorInterleaved2,
    LayoutType.ColumnMajorInterleaved32: LayoutType.RowMajorInterleaved32,
    LayoutType.RowMajorInterleaved32: LayoutType.ColumnMajorInterleaved32,
    LayoutType.ColumnMajorInterleaved64: LayoutType.RowMajorInterleaved64,
    LayoutType.RowMajorInterleaved64: LayoutType.ColumnMajorInterleaved64,
    LayoutType.TensorNHWC: LayoutType.TensorNHWC,
}

#
ShortLayoutTypeNames = {
    LayoutType.ColumnMajor: "n",
    LayoutType.ColumnMajorInterleaved32: "n2",
    LayoutType.ColumnMajorInterleaved32: "n32",
    LayoutType.ColumnMajorInterleaved64: "n64",
    LayoutType.RowMajor: "t",
    LayoutType.RowMajorInterleaved2: "t2",
    LayoutType.RowMajorInterleaved32: "t32",
    LayoutType.RowMajorInterleaved64: "t64",
    LayoutType.TensorNHWC: "nhwc",
    LayoutType.TensorNDHWC: "ndhwc",
    LayoutType.TensorNCHW: "nchw",
    LayoutType.TensorNGHWC: "nghwc",
    LayoutType.TensorNC4HW4: "nc4hw4",
    LayoutType.TensorC4RSK4: "c4rsk4",
    LayoutType.TensorNC8HW8: "nc8hw8",
    LayoutType.TensorNC16HW16: "nc16hw16",
    LayoutType.TensorNC32HW32: "nc32hw32",
    LayoutType.TensorNC64HW64: "nc64hw64",
    LayoutType.TensorC32RSK32: "c32rsk32",
    LayoutType.TensorC64RSK64: "c64rsk64",
    LayoutType.TensorK4RSC4: "k4rsc4",
    LayoutType.TensorCK4RS4: "ck4rs4",
    LayoutType.TensorCK8RS8: "ck8rs8",
    LayoutType.TensorCK16RS16: "ck16rs16",
}

#
ShortComplexLayoutNames = {
    (LayoutType.ColumnMajor, ComplexTransform.none): "n",
    (LayoutType.ColumnMajor, ComplexTransform.conj): "c",
    (LayoutType.RowMajor, ComplexTransform.none): "t",
    (LayoutType.RowMajor, ComplexTransform.conj): "h",
}

###################################################################################################
#
class OpcodeClass(enum.Enum):
    Simt = enum_auto()
    TensorOp = enum_auto()
    WmmaTensorOp = enum_auto()


OpcodeClassNames = {
    OpcodeClass.Simt: "simt",
    OpcodeClass.TensorOp: "tensorop",
    OpcodeClass.WmmaTensorOp: "wmma_tensorop",
}

OpcodeClassTag = {
    OpcodeClass.Simt: "cutlass::arch::OpClassSimt",
    OpcodeClass.TensorOp: "cutlass::arch::OpClassTensorOp",
    OpcodeClass.WmmaTensorOp: "cutlass::arch::OpClassWmmaTensorOp",
}

###################################################################################################

#
class OperationKind(enum.Enum):
    Gemm = enum_auto()
    Conv2d = enum_auto()


#
OperationKindNames = {OperationKind.Gemm: "gemm", OperationKind.Conv2d: "conv2d"}

#
class Target(enum.Enum):
    library = enum_auto()


ArchitectureNames = {
    50: "maxwell",
    60: "pascal",
    61: "pascal",
    70: "volta",
    75: "turing",
    80: "ampere",
}

###################################################################################################

#
def SubstituteTemplate(template, values):
    text = template
    changed = True
    while changed:
        changed = False
        for key, value in values.items():
            regex = "\\$\\{%s\\}" % key
            newtext = re.sub(regex, value, text)
            if newtext != text:
                changed = True
            text = newtext
    return text


###################################################################################################

#
class GemmKind(enum.Enum):
    Gemm = enum_auto()
    Sparse = enum_auto()
    Universal = enum_auto()
    PlanarComplex = enum_auto()
    PlanarComplexArray = enum_auto()
    SplitKParallel = enum_auto()
    GemvBatchedStrided = enum_auto()


#
GemmKindNames = {
    GemmKind.Gemm: "gemm",
    GemmKind.Sparse: "spgemm",
    GemmKind.Universal: "gemm",
    GemmKind.PlanarComplex: "gemm_planar_complex",
    GemmKind.PlanarComplexArray: "gemm_planar_complex_array",
    GemmKind.SplitKParallel: "gemm_split_k_parallel",
    GemmKind.GemvBatchedStrided: "gemv_batched_strided",
}

#
class EpilogueFunctor(enum.Enum):
    LinearCombination = enum_auto()
    LinearCombinationClamp = enum_auto()
    BiasAddLinearCombination = enum_auto()
    BiasAddLinearCombinationRelu = enum_auto()
    BiasAddLinearCombinationHSwish = enum_auto()
    BiasAddLinearCombinationClamp = enum_auto()
    BiasAddLinearCombinationReluClamp = enum_auto()
    BiasAddLinearCombinationHSwishClamp = enum_auto()


#
EpilogueFunctorTag = {
    EpilogueFunctor.LinearCombination: "cutlass::epilogue::thread::LinearCombination",
    EpilogueFunctor.LinearCombinationClamp: "cutlass::epilogue::thread::LinearCombinationClamp",
    EpilogueFunctor.BiasAddLinearCombination: "cutlass::epilogue::thread::BiasAddLinearCombination",
    EpilogueFunctor.BiasAddLinearCombinationRelu: "cutlass::epilogue::thread::BiasAddLinearCombinationRelu",
    EpilogueFunctor.BiasAddLinearCombinationHSwish: "cutlass::epilogue::thread::BiasAddLinearCombinationHSwish",
    EpilogueFunctor.BiasAddLinearCombinationClamp: "cutlass::epilogue::thread::BiasAddLinearCombinationClamp",
    EpilogueFunctor.BiasAddLinearCombinationReluClamp: "cutlass::epilogue::thread::BiasAddLinearCombinationReluClamp",
    EpilogueFunctor.BiasAddLinearCombinationHSwishClamp: "cutlass::epilogue::thread::BiasAddLinearCombinationHSwishClamp",
}

#
ShortEpilogueNames = {
    EpilogueFunctor.LinearCombination: "id",
    EpilogueFunctor.BiasAddLinearCombinationHSwishClamp: "hswish",
    EpilogueFunctor.BiasAddLinearCombinationReluClamp: "relu",
    EpilogueFunctor.BiasAddLinearCombinationClamp: "id",
    EpilogueFunctor.BiasAddLinearCombinationHSwish: "hswish",
    EpilogueFunctor.BiasAddLinearCombinationRelu: "relu",
    EpilogueFunctor.BiasAddLinearCombination: "id",
}


#
class SwizzlingFunctor(enum.Enum):
    Identity1 = enum_auto()
    Identity2 = enum_auto()
    Identity4 = enum_auto()
    Identity8 = enum_auto()
    ConvFpropNCxHWx = enum_auto()
    ConvFpropTrans = enum_auto()
    ConvDgradNCxHWx = enum_auto()
    ConvDgradTrans = enum_auto()
    DepthwiseConvolutionFprop = enum_auto()
    DepthwiseConvolutionDgrad = enum_auto()
    DepthwiseConvolutionWgrad = enum_auto()


#
SwizzlingFunctorTag = {
    SwizzlingFunctor.Identity1: "cutlass::gemm::threadblock::GemmIdentityThreadblockSwizzle<1>",
    SwizzlingFunctor.Identity2: "cutlass::gemm::threadblock::GemmIdentityThreadblockSwizzle<2>",
    SwizzlingFunctor.Identity4: "cutlass::gemm::threadblock::GemmIdentityThreadblockSwizzle<4>",
    SwizzlingFunctor.Identity8: "cutlass::gemm::threadblock::GemmIdentityThreadblockSwizzle<8>",
    SwizzlingFunctor.ConvFpropNCxHWx: "cutlass::conv::threadblock::ConvolutionFpropNCxHWxThreadblockSwizzle",
    SwizzlingFunctor.ConvFpropTrans: "cutlass::conv::threadblock::ConvolutionFpropTransThreadblockSwizzle",
    SwizzlingFunctor.ConvDgradNCxHWx: "cutlass::conv::threadblock::ConvolutionDgradNCxHWxThreadblockSwizzle",
    SwizzlingFunctor.ConvDgradTrans: "cutlass::conv::threadblock::ConvolutionDgradTransThreadblockSwizzle",
    SwizzlingFunctor.DepthwiseConvolutionFprop: "cutlass::conv::threadblock::DepthwiseConvolutionFpropThreadblockSwizzle",
    SwizzlingFunctor.DepthwiseConvolutionDgrad: "cutlass::conv::threadblock::DepthwiseConvolutionDgradThreadblockSwizzle",
    SwizzlingFunctor.DepthwiseConvolutionWgrad: "cutlass::conv::threadblock::DepthwiseConvolutionWgradThreadblockSwizzle",
}

###################################################################################################


class ConvType(enum.Enum):
    Convolution = enum_auto()
    BatchConvolution = enum_auto()
    Local = enum_auto()
    LocalShare = enum_auto()
    DepthwiseConvolution = enum_auto()


ConvTypeTag = {
    ConvType.Convolution: "cutlass::conv::ConvType::kConvolution",
    ConvType.BatchConvolution: "cutlass::conv::ConvType::kBatchConvolution",
    ConvType.Local: "cutlass::conv::ConvType::kLocal",
    ConvType.LocalShare: "cutlass::conv::ConvType::kLocalShare",
    ConvType.DepthwiseConvolution: "cutlass::conv::ConvType::kDepthwiseConvolution",
}

#
class ConvKind(enum.Enum):
    Fprop = enum_auto()
    Dgrad = enum_auto()
    Wgrad = enum_auto()


#
ConvKindTag = {
    ConvKind.Fprop: "cutlass::conv::Operator::kFprop",
    ConvKind.Dgrad: "cutlass::conv::Operator::kDgrad",
    ConvKind.Wgrad: "cutlass::conv::Operator::kWgrad",
}

ConvKindNames = {
    ConvKind.Fprop: "fprop",
    ConvKind.Dgrad: "dgrad",
    ConvKind.Wgrad: "wgrad",
}

#
class IteratorAlgorithm(enum.Enum):
    Analytic = enum_auto()
    Optimized = enum_auto()


#
IteratorAlgorithmTag = {
    IteratorAlgorithm.Analytic: "cutlass::conv::IteratorAlgorithm::kAnalytic",
    IteratorAlgorithm.Optimized: "cutlass::conv::IteratorAlgorithm::kOptimized",
}

IteratorAlgorithmNames = {
    IteratorAlgorithm.Analytic: "analytic",
    IteratorAlgorithm.Optimized: "optimized",
}

#
class StrideSupport(enum.Enum):
    Strided = enum_auto()
    Unity = enum_auto()


#
StrideSupportTag = {
    StrideSupport.Strided: "cutlass::conv::StrideSupport::kStrided",
    StrideSupport.Unity: "cutlass::conv::StrideSupport::kUnity",
}

StrideSupportNames = {StrideSupport.Strided: "", StrideSupport.Unity: "unity_stride"}


class SpecialOptimizeDesc(enum.Enum):
    NoneSpecialOpt = enum_auto()
    ConvFilterUnity = enum_auto()
    DeconvDoubleUpsampling = enum_auto()


SpecialOptimizeDescNames = {
    SpecialOptimizeDesc.NoneSpecialOpt: "none",
    SpecialOptimizeDesc.ConvFilterUnity: "conv_filter_unity",
    SpecialOptimizeDesc.DeconvDoubleUpsampling: "deconv_double_upsampling",
}

SpecialOptimizeDescTag = {
    SpecialOptimizeDesc.NoneSpecialOpt: "cutlass::conv::SpecialOptimizeDesc::NONE",
    SpecialOptimizeDesc.ConvFilterUnity: "cutlass::conv::SpecialOptimizeDesc::CONV_FILTER_UNITY",
    SpecialOptimizeDesc.DeconvDoubleUpsampling: "cutlass::conv::SpecialOptimizeDesc::DECONV_DOUBLE_UPSAMPLING",
}


class ImplicitGemmMode(enum.Enum):
    GemmNT = enum_auto()
    GemmTN = enum_auto()


ImplicitGemmModeNames = {
    ImplicitGemmMode.GemmNT: "gemm_nt",
    ImplicitGemmMode.GemmTN: "gemm_tn",
}

ImplicitGemmModeTag = {
    ImplicitGemmMode.GemmNT: "cutlass::conv::ImplicitGemmMode::GEMM_NT",
    ImplicitGemmMode.GemmTN: "cutlass::conv::ImplicitGemmMode::GEMM_TN",
}

###################################################################################################

#
class MathInstruction:
    def __init__(
        self,
        instruction_shape,
        element_a,
        element_b,
        element_accumulator,
        opcode_class,
        math_operation=MathOperation.multiply_add,
    ):
        self.instruction_shape = instruction_shape
        self.element_a = element_a
        self.element_b = element_b
        self.element_accumulator = element_accumulator
        self.opcode_class = opcode_class
        self.math_operation = math_operation


#
class TileDescription:
    def __init__(
        self,
        threadblock_shape,
        stages,
        warp_count,
        math_instruction,
        min_compute,
        max_compute,
    ):
        self.threadblock_shape = threadblock_shape
        self.stages = stages
        self.warp_count = warp_count
        self.math_instruction = math_instruction
        self.minimum_compute_capability = min_compute
        self.maximum_compute_capability = max_compute

    def procedural_name(self):
        return "%dx%d_%dx%d" % (
            self.threadblock_shape[0],
            self.threadblock_shape[1],
            self.threadblock_shape[2],
            self.stages,
        )


#
class TensorDescription:
    def __init__(
        self, element, layout, alignment=1, complex_transform=ComplexTransform.none
    ):
        self.element = element
        self.layout = layout
        self.alignment = alignment
        self.complex_transform = complex_transform


###################################################################################################


class GlobalCnt:
    cnt = 0
