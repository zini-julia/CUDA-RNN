#include "cuMatrix4d.h"
const int MAX_THREADNUM = Devices::instance()->maxThreadNum();
__global__ void getSumKernel(float* src, float* c, int col){
	extern __shared__ float sm[]; 
	int x = blockIdx.x;
	int y = threadIdx.x;
	int z = blockIdx.y;
	int t = y;
	while(t < col){
		sm[y] = src[t];
		t += blockDim.x;
	}
	__syncthreads();
	t = blockDim.x;
	while(t != 1){
		int skip = (t + 1) >> 1;
		if(y < (t >> 1)){
			sm[y] += sm[y + skip];		
		}
		t = (t+1)>>1;
		__syncthreads();
	}
	if(y == 0){
		c[z*gridDim.x+x] = sm[0];
	}
	__syncthreads();
	if(x == 0 && z == 0){
		int len = gridDim.x * gridDim.y;
		t = y;
		while(t < len){
			sm[y] = c[t];
			t += blockDim.x;
		}
		__syncthreads();
		t = blockDim.x;
		while(t != 1){
			int skip = (t + 1) >> 1;
			if(y < (t >> 1)){
				sm[y] += sm[y + skip];		
			}
			t = (t+1)>>1;
			__syncthreads();
		}
		if(y == 0){
			c[0] = sm[0];
		}
	}
}

float& cuMatrix4d::getSum(){
	int tmpSize = rows() * channals() * ts() * sizeof(float); 	
	if (cuMatrix::tmpMemory.find(tmpSize) == cuMatrix::tmpMemory.end()) {
		cuMatrix::tmpMemory[tmpSize] = make_shared < MatData >(rows() * channals() * ts() ,1);
	}
	int smlen = cols()>rows()*channals()*ts()?cols():rows()*channals()*ts();
	int threadnum = MAX_THREADNUM > cols() ? cols() : MAX_THREADNUM;
	getSumKernel<<<dim3(rows(),channals()*ts()),dim3(threadnum), smlen * sizeof(float)>>>(getDev(),cuMatrix::tmpMemory[tmpSize]->getDev(),cols());
	checkCudaErrors(cudaStreamSynchronize(0));
	getLastCudaError("cuMatrix4d::getSum()");
	cudaMemcpyAsync(&sum,cuMatrix::tmpMemory[tmpSize]->getDev(),sizeof(float),cudaMemcpyDeviceToHost);
	return sum;
}

__global__ void mulKernel(float* dev_x, float* dev_y, float* dev_z, int a2, int cols) {
	int x = blockIdx.x;
	int y = threadIdx.x;
	int z = blockIdx.y;
	while (y < cols) {
		dev_z[z*a2  + x * cols + y] = dev_x[z*a2  + x * cols + y] * dev_y[z*a2  + x * cols + y];
		y += blockDim.x;
	}
}

cuMatrix4d cuMatrix4d::Mul(cuMatrix4d m) {
	assert(m.sizes() == sizes());
	int threadnum = MAX_THREADNUM > cols() ? cols() : MAX_THREADNUM;
	cuMatrix4d res;
	if (cuMatrix::tmpMemory.find(sizes()) != cuMatrix::tmpMemory.end()) {
		res = cuMatrix4d(cuMatrix::tmpMemory[sizes()], rows(), cols(), channals(), ts());
	} else {
		res = cuMatrix4d(rows(), cols(), channals(), ts());
		cuMatrix::tmpMemory[sizes()] = res.data;
	}
	mulKernel<<<dim3(rows(),ts()*channals()), dim3(threadnum)>>>(data->getDev(),
			m.data->getDev(), res.data->getDev(),m.area2D() ,cols());
	checkCudaErrors(cudaStreamSynchronize(0));
	getLastCudaError("cuMatrix4d::Mul(cuMatrix4d)");
	return res;
}
__global__ void t_kernel(float* dev_src, float* dev_res, int res_r, int res_c, int a2){
	int x = blockIdx.x;
	int y = threadIdx.x;
	int z = blockIdx.z;
	while (y < res_c) {
		dev_res[z * a2 + x * res_c + y] = dev_src[z * a2 +y * res_r + x];
		y += blockDim.x;
	}
}

cuMatrix4d cuMatrix4d::t() {
	assert(cols() != 0 && rows() != 0);
	cuMatrix4d res;
	if (cuMatrix::tmpMemory.find(sizes()) != cuMatrix::tmpMemory.end()) {
		res = cuMatrix4d(cuMatrix::tmpMemory[sizes()], cols(), rows(),channals(),ts());
	} else {
		res = cuMatrix4d(cols(), rows(), channals(),ts());
		cuMatrix::tmpMemory[sizes()] = res.data;
	}
	int threadnum = MAX_THREADNUM > res.cols() ? res.cols() : MAX_THREADNUM;
	t_kernel<<<dim3(res.rows(),res.channals()*res.ts()), dim3(threadnum)>>>(data->getDev(),
			res.data->getDev(), res.rows(), res.cols(), area2D());
	checkCudaErrors(cudaStreamSynchronize(0));
	getLastCudaError("pre-element add cuMatrix / float");
	return res;
}
