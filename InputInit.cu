#include "InputInit.h"

__global__ void set_sampleY_kernel(float* sampleY, int* src, int* dev_ran,
		int cols, int ngram) {
	int tid = threadIdx.x;
	int bid = blockIdx.x;
	sampleY[tid * cols + bid] = src[dev_ran[bid] * ngram + tid];
}

__global__ void set_acti0_kernel(float** acti0, int* src, int* dev_ran,
		int cols, int ngram) {
	int tid = threadIdx.x;
	int bid = blockIdx.x;
	float *p = acti0[tid];
	int n = src[dev_ran[bid] * ngram + tid];
	p[n * cols + bid] = 1;
}

void init_acti0(cuMatrixVector& acti_0,cuMatrix& sampleY){
	int bs = Config::instance()->get_batch_size();
	int ngram = Config::instance()->get_ngram();
	int *dev_ran = NULL;
	Samples::instance()->randproductor_init();
	cudaError_t cudaStat = cudaMalloc((void**) &dev_ran, bs * sizeof(int));
	if (cudaStat != cudaSuccess) {
		printf("init_acti0 failed\n");
		exit(0);
	}
	checkCudaErrors(
			cudaMemcpy(dev_ran, Samples::instance()->get_rand(1),
					bs * sizeof(int), cudaMemcpyHostToDevice));
	dim3 block = dim3(bs);
	dim3 thread = dim3(ngram);
	set_acti0_kernel<<<block, thread>>>(acti_0.get_devPoint(),
			Samples::instance()->get_trainX(), dev_ran, bs, ngram);
	checkCudaErrors(cudaDeviceSynchronize());
	getLastCudaError("set_acti0_kernel-2");
	set_sampleY_kernel<<<block, thread>>>(sampleY.getDev(),
			Samples::instance()->get_trainY(), dev_ran, bs, ngram);
	checkCudaErrors(cudaDeviceSynchronize());
	getLastCudaError("set_sampleY_kernel-2");
	checkCudaErrors(cudaFree(dev_ran));
}


__global__ void set_gt_kernel(float** gt_, float* y, int rows, int cols) {
	int tid = threadIdx.x;
	int bid = blockIdx.x;
	assert(tid < rows && bid < cols);
	float* p = gt_[tid];
	int i = y[tid * cols + bid];
	assert(i < 10);
	p[i * cols + bid] = 1.0;
}

void set_groundtruth(cuMatrixVector& gt, cuMatrix& sampleY) {
	dim3 block = dim3(sampleY.cols());
	dim3 thread = dim3(sampleY.rows());
	set_gt_kernel<<<block, thread>>>(gt.get_devPoint(), sampleY.getDev(),
			sampleY.rows(), sampleY.cols());
	checkCudaErrors(cudaDeviceSynchronize());
	getLastCudaError("set_groundtruth ");
}

void initTestdata(vector<vector<int> > &testX, vector<vector<int> > &testY) {
	int *host_X = (int *) malloc(
			sizeof(int) * testX.size() * Config::instance()->get_ngram());
	int *host_Y = (int *) malloc(
			sizeof(int) * testY.size() * Config::instance()->get_ngram());
	for (int i = 0; i < testX.size(); i++) {
		memcpy(host_X + i * 5, &testX[i][0], sizeof(int) * 5);
	}
	for (int i = 0; i < testY.size(); i++) {
		memcpy(host_Y + i * 5, &testY[i][0], sizeof(int) * 5);
	}
	Samples::instance()->testX2gpu(host_X,
			sizeof(int) * testX.size() * Config::instance()->get_ngram());
	Samples::instance()->testY2gpu(host_Y,
			sizeof(int) * testY.size() * Config::instance()->get_ngram());
	free (host_X);
	free (host_Y);
}

void initTraindata(vector<vector<int> > &trainX, vector<vector<int> > &trainY) {
	int *host_X = (int *) malloc(
			sizeof(int) * trainX.size() * Config::instance()->get_ngram());
	int *host_Y = (int *) malloc(
			sizeof(int) * trainY.size() * Config::instance()->get_ngram());
	for (int i = 0; i < trainX.size(); i++) {
		memcpy(host_X + i * 5, &trainX[i][0], sizeof(int) * 5);
	}
	for (int i = 0; i < trainY.size(); i++) {
		memcpy(host_Y + i * 5, &trainY[i][0], sizeof(int) * 5);
	}
	Samples::instance()->trainX2gpu(host_X,
			sizeof(int) * trainX.size() * Config::instance()->get_ngram());
	Samples::instance()->trainY2gpu(host_Y,
			sizeof(int) * trainY.size() * Config::instance()->get_ngram());
	free (host_X);
	free (host_Y);
}


void Data2GPU(vector<vector<int> > &trainX, vector<vector<int> > &trainY,
		vector<vector<int> > &testX, vector<vector<int> > &testY){
	initTestdata(testX,testY);
	initTraindata(trainX,trainY);
}


__global__ void getDataMat_kernel(float** sampleX, int* src, int off, int cols,
		int ngram) {
	int tid = threadIdx.x;
	int bid = blockIdx.x;
	float *p = sampleX[tid];
	int n = src[(off + bid) * ngram + tid];
	p[n * cols + bid] = 1.0;
}

void getDataMat(cuMatrixVector &sampleX, int off, int bs, int n,
		bool flag)
{
		int ngram = Config::instance()->get_ngram();
		for (int i = 0; i < Config::instance()->get_ngram(); i++) {
			sampleX.push_back(new cuMatrix(n, bs));
		}
		sampleX.toGpu();
		dim3 thread = dim3(ngram);
		dim3 block = dim3(bs);
		if (flag) {
			getDataMat_kernel<<<block, thread>>>(sampleX.get_devPoint(),
					Samples::instance()->get_trainX(), off, bs, ngram);
		} else {
			getDataMat_kernel<<<block, thread>>>(sampleX.get_devPoint(),
					Samples::instance()->get_testX(), off, bs, ngram);
		}
		checkCudaErrors(cudaDeviceSynchronize());
		getLastCudaError("getDataMat_kernel ");

}

__global__ void get_res_array_kernel(float* src, int* dev_res, int rows,
		int cols) {
	int bid = blockIdx.x;
	float max = src[bid];
	dev_res[bid] = 0;
	for (int i = 1; i < rows; i++) {
		if (max < src[i * cols + bid]) {
			max = src[i * cols + bid];
			dev_res[bid] = i;
		}
	}
}

void get_res_array(cuMatrix src, int *res, int offset) {
	int *dev_res;
	checkCudaErrors(cudaMalloc((void** )&dev_res, sizeof(int) * src.cols()));
	get_res_array_kernel<<<src.cols(), 1>>>(src.getDev(), dev_res, src.rows(),
			src.cols());
	checkCudaErrors(cudaDeviceSynchronize());
	getLastCudaError("get_res_array ");
	checkCudaErrors(
			cudaMemcpy(res + offset, dev_res, sizeof(int) * src.cols(),
					cudaMemcpyDeviceToHost));
	checkCudaErrors(cudaDeviceSynchronize());
	checkCudaErrors(cudaFree(dev_res));
}

__global__ void set_label_kernel(int* dst, int *src, int num, int threadnum,
		int mid) {
	int bid = blockIdx.x;
	int tid = threadIdx.x;
	int off = bid * threadnum + tid;
	if (off < num) {
		dst[off] = src[off * (mid * 2 + 1) + mid];
	}
}

void set_label(int* label, int size,bool flag) {
	int *dev_label;
	int mid = Config::instance()->get_ngram() / 2;
	int num = size;
	checkCudaErrors(cudaMalloc((void** )&dev_label, sizeof(int) * num));
	int threadnum = Devices::instance()->max_ThreadsPerBlock() > num ? num : Devices::instance()->max_ThreadsPerBlock();
	int blocknum = num / threadnum + 1;
	dim3 blocks(blocknum);
	dim3 threads(threadnum);
	if (flag) {
		set_label_kernel<<<blocks, threads>>>(dev_label,
				Samples::instance()->get_trainY(), num, threadnum, mid);
		checkCudaErrors(cudaDeviceSynchronize());
		getLastCudaError("set_label");
	} else {
		set_label_kernel<<<blocks, threads>>>(dev_label,
				Samples::instance()->get_testY(), num, threadnum, mid);
		checkCudaErrors(cudaDeviceSynchronize());
		getLastCudaError("set_label");
	}
	checkCudaErrors(
			cudaMemcpy(label, dev_label, sizeof(int) * num,
					cudaMemcpyDeviceToHost));
	checkCudaErrors(cudaDeviceSynchronize());
	checkCudaErrors(cudaFree(dev_label));
	getLastCudaError("set_label2");
}