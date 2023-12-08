extern {
  #include <cuda.h>
  #include <stdio.h>
  #include <stdlib.h>
  #include <assert.h>

  static void checkCudaErrors(CUresult err) {
    assert(err == CUDA_SUCCESS);
  }

  static CUdeviceptr getDeviceBufferPointer(void){
    double X;
    CUdeviceptr devBufferX;

    checkCudaErrors(cuMemAlloc(&devBufferX, sizeof(double)));

    srand(0);
    X = rand() % 100;

    checkCudaErrors(cuMemcpyHtoD(devBufferX, &X, sizeof(double)));

    return devBufferX;
  }

  static void **getKernelParams(CUdeviceptr *devBufferX){
    static void* kernelParams[1];
    kernelParams[0] = devBufferX;
    return kernelParams;
  }


  static double getDataFromDevice(CUdeviceptr devBufferX){
    double X;
    cuMemcpyDtoH(&X, devBufferX, sizeof(double));
    return X;
  }

}

pragma "codegen for GPU"
pragma "always resolve function"
export proc add_nums(dst_ptr: c_ptr(real(64))){
  dst_ptr[0] = dst_ptr[0]+5;
}

proc main() {

var output: real(64);

on here.gpus[0] {

  var dummy = [1,2,3]; // to ensure that the CUDA context is attached to the
                       // thread

  var deviceBuffer = getDeviceBufferPointer();

  // arguments are: number of parameters, line no, file no
  var cfg = __primitive("gpu init kernel cfg", 1, 0, 0);

  // 1 is an enum value that says: "pass the address of this to the
  //   kernel_params, while not offloading anything"
  __primitive("gpu arg", cfg, deviceBuffer, 1);

  // arguments are: fatbin path, function name, grid size, block size, arguments
  __primitive("gpu kernel launch flat",
               "add_nums":chpl_c_string,
               1, 1, cfg);
  output = getDataFromDevice(deviceBuffer);

  chpl_gpu_deinit_kernel_cfg(cfg);
}

writeln(output);
}

