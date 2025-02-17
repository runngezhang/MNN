#include "ConvDepthWiseExecution.hpp"
#include "core/ConvolutionCommon.hpp"
#include "Raster.cuh"
#include <float.h>
#include "MNNCUDADefine.hpp"
#include "MNNCUDAFunction.cuh"

namespace MNN {
namespace CUDA {

template<typename T>
__global__ void CONV_DW(const T* input, 
    const half* kernel, 
    const half* bias, 
    T *output, 
    const constBuffer* uConstant,
    DivModFast d_oc,
    DivModFast d_ow,
    DivModFast d_oh
) {
    float maxV = uConstant->maxValue;
    float minV = uConstant->minValue;
    int iw = uConstant->inputSize[0];
    int ih = uConstant->inputSize[1];
    int c = uConstant->channel;
    int c_p = c * PACK_NUMBER;
    int ow = uConstant->outputSize[0];
    int oh = uConstant->outputSize[1];
    int kw = uConstant->kernelSize[0];
    int kh = uConstant->kernelSize[1];
    int dw = uConstant->dilate[0];
    int dh = uConstant->dilate[1];
    int sw = uConstant->stride[0];
    int sh = uConstant->stride[1];
    int pw = uConstant->pad[0];
    int ph = uConstant->pad[1];

    for (size_t index = blockIdx.x * blockDim.x + threadIdx.x; index < uConstant->total/2; index += blockDim.x * gridDim.x) {
        int oz_2, tmp2, oy, ox, tmp1, ob;
        d_oc.divmod(index, tmp1, oz_2);
        d_ow.divmod(tmp1, tmp2, ox);
        d_oh.divmod(tmp2, ob, oy);
        
        int oz = oz_2 << 1;
        int ix = ox * sw - pw;
        int iy = oy * sh - ph;
        float color0 = bias[oz];
        float color1 = bias[oz+1];

        int fxSta = max(0, (UP_DIV(-ix, dw)));
        int fySta = max(0, (UP_DIV(-iy, dh)));
        int fxEnd = min(kw, UP_DIV(iw - ix, dw));
        int fyEnd = min(kh, UP_DIV(ih - iy, dh));
        int fx, fy, fz;
        for (fy=fySta; fy<fyEnd; ++fy) {
            int sy = fy*dh + iy;
            for (fx=fxSta; fx<fxEnd; ++fx) {
                int sx = fx*dw + ix;
                int src_offset = ((ob * ih + sy) * iw + sx) * c_p + oz;
                float inp0 = input[src_offset];
                float inp1 = input[src_offset+1];

                float ker0 = kernel[(fy * kw + fx) * c_p + oz];
                float ker1 = kernel[(fy * kw + fx) * c_p + oz + 1];

                color0 = color0 + inp0 * ker0;
                color1 = color1 + inp1 * ker1;
            }
        }
        color0 = max(color0, minV);
        color0 = min(color0, maxV);

        color1 = max(color1, minV);
        color1 = min(color1, maxV);

        int dst_offset = ((ob * oh + oy) * ow + ox) * c_p + oz;

        output[dst_offset] = color0;
        output[dst_offset+1] = color1;
    }
}

__global__ void CONV_DW_HALF2_OPT(const half2* input, 
    const half2* kernel, 
    const half2* bias, 
    half2 *output, 
    const constBuffer* uConstant,
    DivModFast d_oc,
    DivModFast d_ow,
    DivModFast d_oh
) {
    float maxV = uConstant->maxValue;
    float minV = uConstant->minValue;
    int iw = uConstant->inputSize[0];
    int ih = uConstant->inputSize[1];
    int c = uConstant->channel;
    int c_p = c * PACK_NUMBER / 2;
    int ow = uConstant->outputSize[0];
    int oh = uConstant->outputSize[1];
    int kw = uConstant->kernelSize[0];
    int kh = uConstant->kernelSize[1];
    int sw = uConstant->stride[0];
    int sh = uConstant->stride[1];
    int pw = uConstant->pad[0];
    int ph = uConstant->pad[1];

    for (size_t index = blockIdx.x * blockDim.x + threadIdx.x; index < uConstant->total/2; index += blockDim.x * gridDim.x) {
        int oz_2, tmp2, oy, ox, tmp1, ob;
        d_oc.divmod(index, tmp1, oz_2);
        d_ow.divmod(tmp1, tmp2, ox);
        d_oh.divmod(tmp2, ob, oy);
        
        int oz = oz_2;
        int ix = ox * sw - pw;
        int iy = oy * sh - ph;
        half2 color = bias[oz];

        int fxSta = max(0, -ix);
        int fySta = max(0, -iy);
        int fxEnd = min(kw, iw - ix);
        int fyEnd = min(kh, ih - iy);
        int fx, fy, fz;
        for (fy=fySta; fy<fyEnd; ++fy) {
            int sy = fy + iy;
            for (fx=fxSta; fx<fxEnd; ++fx) {
                int sx = fx + ix;
                int src_offset = ((ob * ih + sy) * iw + sx) * c_p + oz;
                half2 inp = input[src_offset];
                half2 ker = kernel[(fy * kw + fx) * c_p + oz];

                color = __hfma2(inp, ker, color);
            }
        }
        color.x = max(color.x, minV);
        color.x = min(color.x, maxV);

        color.y = max(color.y, minV);
        color.y = min(color.y, maxV);

        int dst_offset = ((ob * oh + oy) * ow + ox) * c_p + oz;
        output[dst_offset] = color;
    }
}


__global__ void CONV_DW3x3_HALF2_OPT(const half2* input, 
    const half2* kernel, 
    const half2* bias, 
    half2 *output, 
    const constBuffer* uConstant,
    DivModFast d_oc,
    DivModFast d_ow,
    DivModFast d_oh
) {
    float maxV = uConstant->maxValue;
    float minV = uConstant->minValue;
    int iw = uConstant->inputSize[0];
    int ih = uConstant->inputSize[1];
    int c = uConstant->channel;
    int c_p = c * PACK_NUMBER / 2;
    int ow = uConstant->outputSize[0];
    int oh = uConstant->outputSize[1];

    for (size_t index = blockIdx.x * blockDim.x + threadIdx.x; index < uConstant->total/4; index += blockDim.x * gridDim.x) {
        int oz_2, tmp2, oy, ox_2, tmp1, ob;
        d_oc.divmod(index, tmp1, oz_2);
        d_ow.divmod(tmp1, tmp2, ox_2);
        d_oh.divmod(tmp2, ob, oy);
        
        int oz = oz_2;
        int ox = ox_2 << 1;
        int ix = ox - 1;
        int iy = oy - 1;
        half2 color0 = bias[oz];
        half2 color1 = color0;

        half2 zero;
        zero.x = (half)0.0;
        zero.y = (half)0.0;

        half2 inp[12];
        half2 ker[3][3];
        for(int j=0; j<3; j++) {
            if(iy < 0 && j==0) {
                for(int i=0; i<4; i++) {
                    inp[i] = zero;
                }
                continue;
            }
            if(iy+2 > ih-1 && j==2) {
                for(int i=0; i<4; i++) {
                    inp[8+i] = zero;
                }
                continue;
            }

            for(int i=0; i<4; i++) {
                if(ix < 0 && i==0) {
                    for(int j=0; j<3; j++) {
                        inp[4*j+0] = zero;
                    }
                    continue;
                }
                if(ix+3 > iw-1 && i==3) {
                    for(int j=0; j<3; j++) {
                        inp[4*j+3] = zero;
                    }
                    continue;
                }
                int src_offset = ((ob * ih + iy+j) * iw + ix+i) * c_p + oz;
                inp[4*j+i] = input[src_offset];
            }
        }

        for(int j=0; j<3; j++) {
            for(int i=0; i<3; i++) {
                ker[j][i] = kernel[(j * 3 + i) * c_p + oz];
            }
        }

        for(int j=0; j<3; j++) {
            for(int i=0; i<3; i++) {
                color0 = __hfma2(inp[4*j+i], ker[j][i], color0);
                color1 = __hfma2(inp[4*j+i+1], ker[j][i], color1);
            }
        }

        color0.x = max(color0.x, minV);
        color0.x = min(color0.x, maxV);
        color0.y = max(color0.y, minV);
        color0.y = min(color0.y, maxV);

        color1.x = max(color1.x, minV);
        color1.x = min(color1.x, maxV);
        color1.y = max(color1.y, minV);
        color1.y = min(color1.y, maxV);

        int dst_offset = ((ob * oh + oy) * ow + ox) * c_p + oz;
        output[dst_offset] = color0;
        output[dst_offset+c_p] = color1;
    }
}

__global__ void CONV_DW_OPT(const float* input, const half* kernel, const half* bias, float *output, const constBuffer* uConstant,
    DivModFast d_oc,
    DivModFast d_ow,
    DivModFast d_oh
    ) {
    float maxV = uConstant->maxValue;
    float minV = uConstant->minValue;
    int iw = uConstant->inputSize[0];
    int ih = uConstant->inputSize[1];
    int ow = uConstant->outputSize[0];
    int oh = uConstant->outputSize[1];
    int kw = uConstant->kernelSize[0];
    int kh = uConstant->kernelSize[1];
    int sw = uConstant->stride[0];
    int sh = uConstant->stride[1];
    int pw = uConstant->pad[0];
    int ph = uConstant->pad[1];
    int c = uConstant->channel;
    int c_p = c * PACK_NUMBER;

    for (size_t index = blockIdx.x * blockDim.x + threadIdx.x; index < uConstant->total / 2; index += blockDim.x * gridDim.x) {
        int oz_2, tmp2, oy, ox, tmp1, ob;
        d_oc.divmod(index, tmp1, oz_2);
        d_ow.divmod(tmp1, tmp2, ox);
        d_oh.divmod(tmp2, ob, oy);

        int oz = oz_2 << 1;
        int ix = ox * sw - pw;
        int iy = oy * sh - ph;
        float color0 = bias[oz];
        float color1 = bias[oz+1];

        int fxSta = max(0, -ix);
        int fySta = max(0, -iy);
        int fxEnd = min(kw, iw - ix);
        int fyEnd = min(kh, ih - iy);
        int fx, fy, fz;
        for (fy=fySta; fy<fyEnd; ++fy) {
            int sy = fy + iy;
            for (fx=fxSta; fx<fxEnd; ++fx) {
                int sx = fx + ix;
                int src_offset = ((ob * ih + sy) * iw + sx) * c_p + oz;
                float inp0 = input[src_offset];
                float inp1 = input[src_offset+1];

                float ker0 = kernel[(fy * kw + fx) * c_p + oz];
                float ker1 = kernel[(fy * kw + fx) * c_p + oz + 1];

                color0 = color0 + inp0 * ker0;
                color1 = color1 + inp1 * ker1;
            }
        }
        color0 = max(color0, minV);
        color0 = min(color0, maxV);

        color1 = max(color1, minV);
        color1 = min(color1, maxV);

        int dst_offset = ((ob * oh + oy) * ow + ox) * c_p + oz;

        output[dst_offset] = color0;
        output[dst_offset+1] = color1;
    }
}

static std::shared_ptr<ConvDepthWiseExecution::Resource> _makeResource(const Op* op, Backend* bn) {
    std::shared_ptr<ConvDepthWiseExecution::Resource> res(new ConvDepthWiseExecution::Resource);
    auto pool = static_cast<CUDABackend*>(bn)->getStaticBufferPool();
    auto runtime = static_cast<CUDABackend*>(bn)->getCUDARuntime();
    auto conv = op->main_as_Convolution2D();
    auto convCommon = conv->common();
    int kernelX = convCommon->kernelX();
    int kernelY = convCommon->kernelY();
    int depth = convCommon->outputCount();
    int depthC = UP_DIV(depth, PACK_NUMBER);
    res->weightTensor.reset(Tensor::createDevice<float>({kernelX * kernelY * depthC * PACK_NUMBER}));
    bool success = bn->onAcquireBuffer(res->weightTensor.get(), Backend::STATIC);
    if (!success) {
        return nullptr;
    }
    res->mFilter = (void *)res->weightTensor.get()->buffer().device;
    FuseRegion reg;
    int offset[8 * PACK_NUMBER];
    auto regionStorage = static_cast<CUDABackend*>(bn)->getStaticBufferPool()->alloc(sizeof(FuseRegion));
    auto offsetGpuStorage = static_cast<CUDABackend*>(bn)->getStaticBufferPool()->alloc(sizeof(offset));
    auto offsetGpu = (uint8_t*)offsetGpuStorage.first + offsetGpuStorage.second;
    //weight host->device
    const float* filterDataPtr = nullptr;
    int weightSize = 0;
    std::shared_ptr<ConvolutionCommon::Int8Common> quanCommon;
    ConvolutionCommon::getConvParameters(&quanCommon, conv, &filterDataPtr, &weightSize);
    auto tempWeightStorage = pool->alloc(depthC * PACK_NUMBER * kernelY * kernelX * sizeof(float));
    auto tempWeight = (uint8_t*)tempWeightStorage.first + tempWeightStorage.second;
    cuda_check(cudaMemset(tempWeight, 0, depthC * PACK_NUMBER * kernelY * kernelX * sizeof(float)));
    cuda_check(cudaMemcpy(tempWeight, filterDataPtr, weightSize*sizeof(float), cudaMemcpyHostToDevice));
    reg.size[0] = 1;
    reg.size[1] = kernelY * kernelX;
    reg.size[2] = depthC * PACK_NUMBER;
    reg.srcStride[0] = 0;
    reg.srcStride[1] = 1;
    reg.srcStride[2] = kernelY * kernelX;
    reg.dstStride[0] = 0;
    reg.dstStride[1] = depthC * PACK_NUMBER;
    reg.dstStride[2] = 1;
    offset[0] = 1;
    offset[1] = kernelY * kernelX;
    offset[2] = depth;
    offset[3] = 0;
    offset[4] = 1;
    offset[5] = reg.size[1];
    offset[6] = reg.size[2];
    offset[7] = 0;
    reg.fuseNumber = 1;

    runtime->memcpy((uint8_t*)regionStorage.first + regionStorage.second, &reg, sizeof(FuseRegion), MNNMemcpyHostToDevice, true);
    runtime->memcpy(offsetGpu, offset, 8 * sizeof(int), MNNMemcpyHostToDevice, true);
    FuseRasterBlitFloatToHalf((uint8_t*)res->mFilter, (uint8_t*)tempWeight, (FuseRegion*)((uint8_t*)regionStorage.first + regionStorage.second), offsetGpu, runtime);
    pool->free(tempWeightStorage);
    res->biasTensor.reset(Tensor::createDevice<float>({depthC * PACK_NUMBER}));
    success = bn->onAcquireBuffer(res->biasTensor.get(), Backend::STATIC);
    res->mBias = (void *)res->biasTensor.get()->buffer().device;
    if (!success) {
        return nullptr;
    }
    if(conv->bias() != nullptr) {
        auto tempBiasStorage = pool->alloc(depth * sizeof(float));
        auto tempBias = (uint8_t*)tempBiasStorage.first + tempBiasStorage.second;
        cuda_check(cudaMemcpy(tempBias, conv->bias()->data(), conv->bias()->size()*sizeof(float), cudaMemcpyHostToDevice));
        reg.size[0] = 1;
        reg.size[1] = 1;
        reg.size[2] = depthC * PACK_NUMBER;
        reg.srcStride[0] = 0;
        reg.srcStride[1] = 0;
        reg.srcStride[2] = 1;
        reg.dstStride[0] = 0;
        reg.dstStride[1] = 0;
        reg.dstStride[2] = 1;
        offset[0] = 1;
        offset[1] = 1;
        offset[2] = conv->bias()->size();
        offset[3] = 0;
        offset[4] = 1;
        offset[5] = 1;
        offset[6] = reg.size[2];
        offset[7] = 0;
        reg.fuseNumber = 1;
        runtime->memcpy((uint8_t*)regionStorage.first + regionStorage.second, &reg, sizeof(FuseRegion), MNNMemcpyHostToDevice, true);
        runtime->memcpy(offsetGpu, offset, 8 * sizeof(int), MNNMemcpyHostToDevice, true);
        FuseRasterBlitFloatToHalf((uint8_t*)res->mBias, (uint8_t*)tempBias, (FuseRegion*)((uint8_t*)regionStorage.first + regionStorage.second), offsetGpu, runtime);
        pool->free(tempBiasStorage);
    }
    static_cast<CUDABackend*>(bn)->getStaticBufferPool()->free(regionStorage);
    static_cast<CUDABackend*>(bn)->getStaticBufferPool()->free(offsetGpuStorage);
    return res;
}

ConvDepthWiseExecution::ConvDepthWiseExecution(const Op* op, Backend* bn, std::shared_ptr<Resource> resource) : Execution(bn) {
    mOp = op;
    mResource = resource;
    auto pool = static_cast<CUDABackend*>(bn)->getStaticBufferPool();
    mConstBuffer = pool->alloc(sizeof(constBuffer));
}
ConvDepthWiseExecution::~ ConvDepthWiseExecution() {
    auto pool = static_cast<CUDABackend*>(backend())->getStaticBufferPool();
    pool->free(mConstBuffer);
}

ErrorCode ConvDepthWiseExecution::onResize(const std::vector<Tensor *> &inputs, const std::vector<Tensor *> &outputs) {
    auto pad = ConvolutionCommon::convolutionPad(inputs[0], outputs[0], mOp->main_as_Convolution2D()->common());
    auto conv = mOp->main_as_Convolution2D();
    auto convCommon = mOp->main_as_Convolution2D()->common();
    int channel = inputs[0]->channel();
    int channelDiv = UP_DIV(channel, PACK_NUMBER);
    parameters.pad[0] = pad.first;
    parameters.pad[1] = pad.second;
    parameters.kernelSize[0] = convCommon->kernelX();
    parameters.kernelSize[1] = convCommon->kernelY();
    parameters.stride[0] = convCommon->strideX();
    parameters.stride[1] = convCommon->strideY();
    parameters.dilate[0] = convCommon->dilateX();
    parameters.dilate[1] = convCommon->dilateY();
    parameters.inputSize[0] = inputs[0]->width();
    parameters.inputSize[1] = inputs[0]->height();
    parameters.channel = channelDiv;
    parameters.outputSize[0] = outputs[0]->width();
    parameters.outputSize[1] = outputs[0]->height();
    parameters.batch = inputs[0]->batch();

    parameters.total = parameters.batch * parameters.outputSize[1] * parameters.outputSize[0] * parameters.channel * PACK_NUMBER;
    if (static_cast<CUDABackend*>(backend())->useFp16()) {
        // Do nothing
    } else {
        parameters.minValue = -FLT_MAX;
        parameters.maxValue = FLT_MAX;
    }
    if (convCommon->relu()) {
        parameters.minValue = 0.0f;
    }
    if (convCommon->relu6()) {
        parameters.minValue = 0.0f;
        parameters.maxValue = 6.0f;
    }

    auto runtime = static_cast<CUDABackend*>(backend())->getCUDARuntime();
    runtime->memcpy((uint8_t*)mConstBuffer.first + mConstBuffer.second, &parameters, sizeof(constBuffer), MNNMemcpyHostToDevice);
    mTotalCount = parameters.total;
    //MNN_PRINT("%d-%d-%d-%d, %d-%d-%d-%d-%d\n", parameters.kernelSize[0], parameters.kernelSize[1], parameters.stride[0], parameters.stride[1], parameters.inputSize[0], parameters.inputSize[1], channel, parameters.outputSize[0], parameters.outputSize[1]);
    return NO_ERROR;
}

ErrorCode ConvDepthWiseExecution::onExecute(const std::vector<Tensor *> &inputs, const std::vector<Tensor *> &outputs) {
    auto runtime = static_cast<CUDABackend*>(backend())->getCUDARuntime();
    auto& prop = runtime->prop();
    int limitThreads = UP_DIV(mTotalCount, prop.multiProcessorCount);
    int threads_num = ALIMIN(prop.maxThreadsPerBlock/2, limitThreads);
    int block_num = prop.multiProcessorCount;
    auto constPtr = (uint8_t*)mConstBuffer.first + mConstBuffer.second;

    DivModFast d_oc(parameters.channel * PACK_NUMBER / 2);
    DivModFast d_ow(parameters.outputSize[0]);
    DivModFast d_oh(parameters.outputSize[1]);

    if (static_cast<CUDABackend*>(backend())->useFp16()) {
        if(parameters.kernelSize[0]==3 && parameters.kernelSize[1]==3 && parameters.stride[0]==1 && parameters.stride[1]==1 && parameters.pad[0]==1 && parameters.pad[1]==1 && parameters.outputSize[0] % 2 ==0) {
            DivModFast d_ow2(parameters.outputSize[0]/2);

            CONV_DW3x3_HALF2_OPT<<<block_num, threads_num>>>((const half2*)inputs[0]->deviceId(), (const half2*)mResource->mFilter,
                (const half2*)mResource->mBias, (half2*)outputs[0]->deviceId(), (const constBuffer*)(constPtr),
                d_oc, d_ow2, d_oh);
            checkKernelErrors;
            return NO_ERROR;
        }
        if(parameters.dilate[0] == 1 && parameters.dilate[1] == 1) { 
            CONV_DW_HALF2_OPT<<<block_num, threads_num>>>((const half2*)inputs[0]->deviceId(), (const half2*)mResource->mFilter,
                (const half2*)mResource->mBias, (half2*)outputs[0]->deviceId(), (const constBuffer*)(constPtr),
                d_oc, d_ow, d_oh);//_HALF_OPT
            checkKernelErrors;
        } else {
            CONV_DW<<<block_num, threads_num>>>((const half*)inputs[0]->deviceId(), (const half*)mResource->mFilter,
                (const half*)mResource->mBias, (half*)outputs[0]->deviceId(), (const constBuffer*)(constPtr),
                d_oc, d_ow, d_oh);
            checkKernelErrors;
        }
        return NO_ERROR;
    }

    if (inputs.size() == 1) {
        // block_num = runtime->blocks_num(mTotalCount);
        // threads_num = runtime->threads_num();
        if(parameters.dilate[0] == 1 && parameters.dilate[1] == 1) { 
            CONV_DW_OPT<<<block_num, threads_num>>>((const float*)inputs[0]->deviceId(), (const half*)mResource->mFilter,
                (const half*)mResource->mBias, (float*)outputs[0]->deviceId(), (const constBuffer*)(constPtr),
                d_oc, d_ow, d_oh);
            checkKernelErrors;
        } else {
            CONV_DW<<<block_num, threads_num>>>((const float*)inputs[0]->deviceId(), (const half*)mResource->mFilter,
                (const half*)mResource->mBias, (float*)outputs[0]->deviceId(), (const constBuffer*)(constPtr),
                d_oc, d_ow, d_oh);
            checkKernelErrors;
        }
    }
    return NO_ERROR;
}

class ConvDepthWiseExecutionCreator : public CUDABackend::Creator {
public:
    virtual Execution* onCreate(const std::vector<Tensor*>& inputs, const std::vector<Tensor*>& outputs,
                                const MNN::Op* op, Backend* backend) const override {
        if (inputs.size() > 1) {
            return nullptr;
        }
        auto res = _makeResource(op, backend);
        if (nullptr == res) {
            return nullptr;
        }
        return new ConvDepthWiseExecution(op, backend, res);
    }
};

static CUDACreatorRegister<ConvDepthWiseExecutionCreator> __init(OpType_ConvolutionDepthwise);
}
}