#pragma once

#include <c10/cuda/CUDAStream.h>
#include <cuda.h>
#include <torch/all.h>

#include "cutlass/bfloat16.h"
#include "cutlass/float8.h"

template <typename ElementA, typename ElementB, typename ElementC, typename ElementAccumulator>
__global__ void int4_fp8_get_group_gemm_starts(
    int32_t* expert_offsets,
    ElementA** a_offsets,
    ElementB** b_offsets,
    ElementC** out_offsets,
    ElementAccumulator** a_scales_offsets,
    cutlass::bfloat16_t** b_scales_offsets,
    ElementA* a_base_as_int,
    ElementB* b_base_as_int,
    ElementC* out_base_as_int,
    ElementAccumulator* a_scales_base_as_int,
    cutlass::bfloat16_t* b_scales_base_as_int,
    int64_t n,
    int64_t k,
    bool per_act_token,
    bool per_out_ch) {
  int expert_id = threadIdx.x;
  int32_t expert_offset = expert_offsets[expert_id];

  a_offsets[expert_id] = a_base_as_int + expert_offset * k;
  b_offsets[expert_id] = b_base_as_int + expert_id * k * n / 2;
  out_offsets[expert_id] = out_base_as_int + expert_offset * n;
  a_scales_offsets[expert_id] = a_scales_base_as_int + (per_act_token ? expert_offset : 0);
  b_scales_offsets[expert_id] = b_scales_base_as_int + (per_out_ch ? expert_id * n * 4 * k / 512 : expert_id);
}

#define __CALL_W4A8_GET_STARTS_KERNEL(TENSOR_C_TYPE, C_TYPE)                              \
  else if (out_tensors.dtype() == TENSOR_C_TYPE) {                                        \
    int4_fp8_get_group_gemm_starts<cutlass::float_e4m3_t, cutlass::int8_t, C_TYPE, float> \
        <<<1, num_experts, 0, stream>>>(                                                  \
            static_cast<int32_t*>(expert_offsets.data_ptr()),                             \
            static_cast<cutlass::float_e4m3_t**>(a_ptrs.data_ptr()),                      \
            static_cast<cutlass::int8_t**>(b_ptrs.data_ptr()),                            \
            static_cast<C_TYPE**>(out_ptrs.data_ptr()),                                   \
            static_cast<float**>(a_scales_ptrs.data_ptr()),                               \
            static_cast<cutlass::bfloat16_t**>(b_scales_ptrs.data_ptr()),                 \
            static_cast<cutlass::float_e4m3_t*>(a_tensors.data_ptr()),                    \
            static_cast<cutlass::int8_t*>(b_tensors.data_ptr()),                          \
            static_cast<C_TYPE*>(out_tensors.data_ptr()),                                 \
            static_cast<float*>(a_scales.data_ptr()),                                     \
            static_cast<cutlass::bfloat16_t*>(b_scales.data_ptr()),                       \
            out_tensors.size(1),                                                          \
            a_tensors.size(1),                                                            \
            per_act_token,                                                                \
            per_out_ch);                                                                  \
  }

namespace {

void run_int4_fp8_get_group_gemm_starts(
    torch::Tensor const& expert_offsets,
    torch::Tensor& a_ptrs,
    torch::Tensor& b_ptrs,
    torch::Tensor& out_ptrs,
    torch::Tensor& a_scales_ptrs,
    torch::Tensor& b_scales_ptrs,
    torch::Tensor const& a_tensors,
    torch::Tensor const& b_tensors,
    torch::Tensor& out_tensors,
    torch::Tensor const& a_scales,
    torch::Tensor const& b_scales) {
  TORCH_CHECK(a_tensors.dtype() == torch::kFloat8_e4m3fn);
  TORCH_CHECK(b_tensors.dtype() == torch::kInt8);
  TORCH_CHECK(a_scales.dtype() == torch::kFloat32);
  TORCH_CHECK(b_scales.dtype() == torch::kBFloat16);

  int num_experts = static_cast<int>(expert_offsets.size(0));
  bool per_act_token = a_scales.numel() != 1;
  bool per_out_ch = b_scales.numel() != num_experts;

  auto stream = at::cuda::getCurrentCUDAStream(expert_offsets.device().index());

  if (false) {
  }
  __CALL_W4A8_GET_STARTS_KERNEL(torch::kBFloat16, cutlass::bfloat16_t)
  __CALL_W4A8_GET_STARTS_KERNEL(torch::kFloat16, half)
  else {
    TORCH_CHECK(false, "Invalid output type (must be float16 or bfloat16)");
  }
}

}  // namespace
