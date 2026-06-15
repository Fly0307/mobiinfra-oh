/*
 * Adapted from CANNKit samplecode-clientdemo-cpp.
 * Uses HarmonyOS Neural Network Runtime (oh_nn) to load and run OMC models.
 */

#include "HIAIModelManager.h"
#include <hilog/log.h>
#include <cstring>
#include <cstdlib>
#include "neural_network_runtime/neural_network_core.h"
#include "CANNKit/hiai_options.h"

#undef LOG_DOMAIN
#define LOG_DOMAIN 0x0000
#undef LOG_TAG
#define LOG_TAG "MobiInfra"
#define HIAI_LOGI(fmt, ...) OH_LOG_INFO(LOG_APP, "[MobiInfra][HIAIModel] " fmt, ##__VA_ARGS__)
#define HIAI_LOGE(fmt, ...) OH_LOG_ERROR(LOG_APP, "[MobiInfra][HIAIModel] " fmt, ##__VA_ARGS__)

HIAIModelManager &HIAIModelManager::GetInstance() {
    static HIAIModelManager instance;
    return instance;
}

namespace {

size_t GetDeviceID() {
    // 遍历 HarmonyOS NNRT 设备，优先选择 HiAI NPU 设备 HIAI_F。
    size_t deviceID = 0;
    const size_t *allDevicesID = nullptr;
    uint32_t deviceCount = 0;
    OH_NN_ReturnCode ret = OH_NNDevice_GetAllDevicesID(&allDevicesID, &deviceCount);
    if (ret != OH_NN_SUCCESS || allDevicesID == nullptr) {
        HIAI_LOGE("OH_NNDevice_GetAllDevicesID failed");
        return deviceID;
    }
    for (uint32_t i = 0; i < deviceCount; i++) {
        const char *name = nullptr;
        ret = OH_NNDevice_GetName(allDevicesID[i], &name);
        if (ret != OH_NN_SUCCESS || name == nullptr) continue;
        HIAI_LOGI("Found device: %{public}s", name);
        if (std::string(name) == "HIAI_F") {
            deviceID = allDevicesID[i];
            HIAI_LOGI("Selected NPU device: %{public}s (id=%{public}zu)", name, deviceID);
            break;
        }
    }
    return deviceID;
}

void DestroyTensors(std::vector<NN_Tensor*> &tensors) {
    // NN_Tensor 由 OH_NNTensor_Create 分配，必须逐个 Destroy 后再清空 vector。
    for (auto t : tensors) {
        OH_NNTensor_Destroy(&t);
    }
    tensors.clear();
}
} // anonymous namespace

// ================================================================
// Public API
// ================================================================

OH_NN_ReturnCode HIAIModelManager::LoadModelFromBuffer(uint8_t *modelData, size_t modelSize) {
    // 从 .omc 内存 buffer 构建离线模型，编译完成后保存 executor_ 供后续 RunSync。
    if (executor_ != nullptr) {
        HIAI_LOGE("executor already initialized");
        return OH_NN_FAILED;
    }
    if (modelData == nullptr || modelSize == 0) {
        HIAI_LOGE("invalid offline model buffer");
        return OH_NN_FAILED;
    }
    // (compatibility check skipped — CANNKit header may not be available)

    // OMC 已经是离线模型，这里直接从内存 buffer 构造 Compilation。
    OH_NNCompilation *compilation = OH_NNCompilation_ConstructWithOfflineModelBuffer(modelData, modelSize);
    if (compilation == nullptr) {
        HIAI_LOGE("OH_NNCompilation_ConstructWithOfflineModelBuffer failed");
        return OH_NN_FAILED;
    }

    size_t deviceID = GetDeviceID();
    if (deviceID == 0) {
        HIAI_LOGE("GetDeviceID failed — no HIAI_F device found");
        OH_NNCompilation_Destroy(&compilation);
        return OH_NN_FAILED;
    }
    deviceID_ = deviceID;

    OH_NN_ReturnCode ret = OH_NNCompilation_SetDevice(compilation, deviceID);
    if (ret != OH_NN_SUCCESS) {
        HIAI_LOGE("OH_NNCompilation_SetDevice failed");
        OH_NNCompilation_Destroy(&compilation);
        return ret;
    }

    // 设置 NPU 优先执行，逻辑与 CANNKit demo 保持一致。
    HiAI_BandMode bandMode = HiAI_BandMode::HIAI_BANDMODE_NORMAL;
    ret = HMS_HiAIOptions_SetBandMode(compilation, bandMode);
    HIAI_LOGI("SetBandMode ret=%{public}d", ret);
    if (ret == OH_NN_SUCCESS) {
        std::vector<HiAI_ExecuteDevice> devices {HiAI_ExecuteDevice::HIAI_EXECUTE_DEVICE_NPU};
        ret = HMS_HiAIOptions_SetModelDeviceOrder(compilation, devices.data(), devices.size());
        HIAI_LOGI("SetModelDeviceOrder(NPU) ret=%{public}d", ret);
    }

    ret = OH_NNCompilation_Build(compilation);
    if (ret != OH_NN_SUCCESS) {
        HIAI_LOGE("OH_NNCompilation_Build failed, ret=%{public}d", ret);
        OH_NNCompilation_Destroy(&compilation);
        return ret;
    }

    executor_ = OH_NNExecutor_Construct(compilation);
    if (executor_ == nullptr) {
        HIAI_LOGE("OH_NNExecutor_Construct failed");
        OH_NNCompilation_Destroy(&compilation);
        return OH_NN_FAILED;
    }
    OH_NNCompilation_Destroy(&compilation);
    HIAI_LOGI("LoadModelFromBuffer success");
    return OH_NN_SUCCESS;
}

OH_NN_ReturnCode HIAIModelManager::InitIOTensors() {
    // 根据 executor 描述自动创建输入/输出 tensor，调用方只需要按 index 写入数据。
    if (executor_ == nullptr) {
        HIAI_LOGE("executor not initialized");
        return OH_NN_FAILED;
    }
    if (!inputTensors_.empty()) { DestroyTensors(inputTensors_); }
    if (!outputTensors_.empty()) { DestroyTensors(outputTensors_); }

    // --- Inputs ---
    size_t inputCount = 0;
    OH_NN_ReturnCode ret = OH_NNExecutor_GetInputCount(executor_, &inputCount);
    if (ret != OH_NN_SUCCESS) {
        HIAI_LOGE("GetInputCount failed");
        return ret;
    }
    for (size_t i = 0; i < inputCount; ++i) {
        NN_TensorDesc *desc = OH_NNExecutor_CreateInputTensorDesc(executor_, i);
        NN_Tensor *t = OH_NNTensor_Create(deviceID_, desc);
        if (t) inputTensors_.push_back(t);
        if (desc) OH_NNTensorDesc_Destroy(&desc);
    }

    // --- Outputs ---
    size_t outputCount = 0;
    ret = OH_NNExecutor_GetOutputCount(executor_, &outputCount);
    if (ret != OH_NN_SUCCESS) return ret;
    for (size_t i = 0; i < outputCount; ++i) {
        NN_TensorDesc *desc = OH_NNExecutor_CreateOutputTensorDesc(executor_, i);
        NN_Tensor *t = OH_NNTensor_Create(deviceID_, desc);
        if (t) outputTensors_.push_back(t);
        if (desc) OH_NNTensorDesc_Destroy(&desc);
    }

    HIAI_LOGI("InitIOTensors success: %{public}zu in, %{public}zu out",
                inputTensors_.size(), outputTensors_.size());
    return OH_NN_SUCCESS;
}

OH_NN_ReturnCode HIAIModelManager::SetInputData(int idx, const float *data, size_t count) {
    // 当前测试链路只写 float 输入；count=0 时按 tensor buffer 大小自动填满。
    if (idx < 0 || (size_t)idx >= inputTensors_.size()) return OH_NN_FAILED;
    if (data == nullptr) return OH_NN_FAILED;
    void *buf = OH_NNTensor_GetDataBuffer(inputTensors_[idx]);
    size_t sz = 0;
    OH_NNTensor_GetSize(inputTensors_[idx], &sz);
    if (!buf) return OH_NN_FAILED;
    size_t actualCount = sz / sizeof(float);
    if (count == 0) count = actualCount;  // auto-size
    if (count > actualCount) count = actualCount;
    std::memcpy(buf, data, count * sizeof(float));
    return OH_NN_SUCCESS;
}

OH_NN_ReturnCode HIAIModelManager::RunModel() {
    // 同步执行 OMC 模型，主要用于和 MNN CPU 输出做精度/性能对比。
    if (!executor_ || inputTensors_.empty() || outputTensors_.empty()) {
        HIAI_LOGE("model/io not ready");
        return OH_NN_FAILED;
    }
    HIAI_LOGI("RunSync BEGIN");
    OH_NN_ReturnCode ret = OH_NNExecutor_RunSync(executor_,
        inputTensors_.data(), inputTensors_.size(),
        outputTensors_.data(), outputTensors_.size());
    HIAI_LOGI("RunSync END ret=%{public}d", ret);
    return ret;
}

std::vector<float> HIAIModelManager::GetOutputData(int idx) {
    // 输出 tensor buffer 转成扁平 float vector，便于上层做误差统计。
    std::vector<float> out;
    if (idx < 0 || (size_t)idx >= outputTensors_.size()) return out;
    void *d = OH_NNTensor_GetDataBuffer(outputTensors_[idx]);
    size_t sz = 0;
    OH_NNTensor_GetSize(outputTensors_[idx], &sz);
    if (!d || sz == 0) return out;
    float *fd = static_cast<float*>(d);
    out.assign(fd, fd + sz / sizeof(float));
    return out;
}

std::vector<int64_t> HIAIModelManager::GetOutputShape(int idx) {
    std::vector<int64_t> shape;
    if (idx < 0 || (size_t)idx >= outputTensors_.size()) return shape;
    NN_TensorDesc *desc = OH_NNTensor_GetTensorDesc(outputTensors_[idx]);
    if (!desc) return shape;
    int32_t *dims = nullptr;
    size_t dimCount = 0;
    OH_NN_ReturnCode ret = OH_NNTensorDesc_GetShape(desc, &dims, &dimCount);
    if (ret == OH_NN_SUCCESS && dims) {
        shape.assign(dims, dims + dimCount);
        free(dims);
    }
    OH_NNTensorDesc_Destroy(&desc);
    return shape;
}

int HIAIModelManager::GetInputCount() {
    return (int)inputTensors_.size();
}

size_t HIAIModelManager::GetInputSize(int idx) {
    if (idx < 0 || (size_t)idx >= inputTensors_.size()) return 0;
    size_t sz = 0;
    OH_NNTensor_GetSize(inputTensors_[idx], &sz);
    return sz;
}

int HIAIModelManager::GetOutputCount() {
    return (int)outputTensors_.size();
}

OH_NN_ReturnCode HIAIModelManager::UnloadModel() {
    DestroyTensors(inputTensors_);
    DestroyTensors(outputTensors_);
    OH_NNExecutor_Destroy(&executor_);
    executor_ = nullptr;
    return OH_NN_SUCCESS;
}
