/* 
 * ------------------------------------------------------------
 * Author: Breno Vargas Gemelgo
 * CUDA Implementation: Lattice Boltzmann Method
 * Module: Moments and Collision Step for Bubble Simulation
 * 
 * To compile and integrate with MATLAB, use the following:
 * nvcc -ptx gpuMomCollision.cu -o gpuMomCollision.ptx
 * ------------------------------------------------------------
 */

#include <cuda_runtime.h>
#include <math.h>

__global__ void momCollision(
        double *rho, double *ux, double *uy, double *uz,  
        double *ffx, double *ffy, double *ffz, double *f,         
        int nx, int ny, int nz, 
        double cssq, double *cix, double *ciy, double *ciz, double *w,
        double *pxx, double *pyy, double *pzz, double *pxy, double *pxz, double *pyz,
        int fpoints,
        double omega, double sharp_c, double *w_g, double *phi,
        double *normx, double *normy, double *normz, double *g,
        int gpoints
    ) {
    
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    int idx = i + nx * (j + ny * k);
    #define F_IDX(i,j,k,l) ((i) + nx * ((j) + ny * ((k) + nz * (l))))

    // moments
    if (i > 0 && i < nx-1 && j > 0 && j < ny-1 && k > 0 && k < nz-1) {

        ux[idx] = (
            (f[F_IDX(i,j,k,1)] + f[F_IDX(i,j,k,15)] + f[F_IDX(i,j,k,9)] + f[F_IDX(i,j,k,7)] + f[F_IDX(i,j,k,13)]) -
            (f[F_IDX(i,j,k,2)] + f[F_IDX(i,j,k,10)] + f[F_IDX(i,j,k,16)] + f[F_IDX(i,j,k,14)] + f[F_IDX(i,j,k,7)])
        ) / rho[idx] +
        ffx[idx] * 0.5 / rho[idx];
        uy[idx] = (
            (f[F_IDX(i,j,k,3)] + f[F_IDX(i,j,k,7)] + f[F_IDX(i,j,k,14)] + f[F_IDX(i,j,k,17)] + f[F_IDX(i,j,k,11)]) -
            (f[F_IDX(i,j,k,4)] + f[F_IDX(i,j,k,13)] + f[F_IDX(i,j,k,8)] + f[F_IDX(i,j,k,12)] + f[F_IDX(i,j,k,18)])
        ) / rho[idx] +
        ffy[idx] * 0.5 / rho[idx];
        uz[idx] = (
            (f[F_IDX(i,j,k,6)] + f[F_IDX(i,j,k,15)] + f[F_IDX(i,j,k,10)] + f[F_IDX(i,j,k,17)] + f[F_IDX(i,j,k,12)]) -
            (f[F_IDX(i,j,k,5)] + f[F_IDX(i,j,k,9)] + f[F_IDX(i,j,k,16)] + f[F_IDX(i,j,k,11)] + f[F_IDX(i,j,k,18)])
        ) / rho[idx] +
        ffz[idx] * 0.5 / rho[idx];

        double fneq[19];
        double uu = 0.5 * (pow(ux[idx],2) + pow(uy[idx],2) + pow(uz[idx],2)) / cssq;

        for (int n = 0; n < fpoints; n++) { 
            rho[idx] += f[idx + n * nx * ny * nz]; 
        }

        for (int l = 0; l < fpoints; l++) {
            double udotc = (ux[idx] * cix[l] + uy[idx] * ciy[l] + uz[idx] * ciz[l]) / cssq;
            double HeF = (w[l] * (rho[idx] + rho[idx] * (udotc + 0.5 * pow(udotc,2) - uu)))
                     * ((cix[l] - ux[idx]) * ffx[idx] + 
                        (ciy[l] - uy[idx]) * ffy[idx] + 
                        (ciz[l] - uz[idx]) * ffz[idx] 
                       ) / (rho[idx] * cssq);
            double feq = w[l] * (rho[idx] + rho[idx] * (udotc + 0.5 * pow(udotc,2) - uu)) - 0.5 * HeF;
            fneq[l] = f[F_IDX(i,j,k,l)] - feq;
        }

        pxx[idx] = fneq[2] + fneq[3] + fneq[8] + fneq[9] + fneq[10] + fneq[11] + fneq[14] + fneq[15] + fneq[16] + fneq[17];
        pyy[idx] = fneq[4] + fneq[5] + fneq[8] + fneq[9] + fneq[12] + fneq[13] + fneq[14] + fneq[15] + fneq[18] + fneq[19];
        pzz[idx] = fneq[6] + fneq[7] + fneq[10] + fneq[11] + fneq[12] + fneq[13] + fneq[16] + fneq[17] + fneq[18] + fneq[19];
        pxy[idx] = fneq[8] + fneq[9] - fneq[14] - fneq[15];
        pxz[idx] = fneq[10] + fneq[11] - fneq[16] - fneq[17];
        pyz[idx] = fneq[12] + fneq[13] - fneq[18] - fneq[19];

    }

    // collision
    if (i > 0 && i < nx-1 && j > 0 && j < ny-1 && k > 0 && k < nz-1) {

        double uu = 0.5 * (pow(ux[idx],2) + pow(uy[idx],2) + pow(uz[idx],2)) / cssq;

        for (int l = 0; l < fpoints; l++) {
            double udotc = (ux[idx] * cix[l] + uy[idx] * ciy[l] + uz[idx] * ciz[l]) / cssq;
            double feq = w[l] * (rho[idx] + rho[idx] * (udotc + 0.5 * pow(udotc,2) - uu));
            double HeF = 0.5 * (w[l] * (rho[idx] + rho[idx] * (udotc + 0.5 * pow(udotc,2) - uu)))
                     * ((cix[l] - ux[idx]) * ffx[idx] + 
                        (ciy[l] - uy[idx]) * ffy[idx] + 
                        (ciz[l] - uz[idx]) * ffz[idx] 
                       ) / (rho[idx] * cssq);
            double fneq = (cix[l] * cix[l] - cssq) * pxx[idx] + 
                          (ciy[l] * ciy[l] - cssq) * pyy[idx] + 
                          (ciz[l] * ciz[l] - cssq) * pzz[idx] + 
                          2 * cix[l] * ciy[l] * pxy[idx] + 
                          2 * cix[l] * ciz[l] * pxz[idx] + 
                          2 * ciy[l] * ciz[l] * pyz[idx];
            f[F_IDX(i+static_cast<int>(cix[l]),
                    j+static_cast<int>(ciy[l]),
                    k+static_cast<int>(ciz[l]),
                    l)] = feq + (1-omega) * (w[l] / (2*pow(cssq,2))) * fneq + HeF;
        }

        for (int l = 0; l < gpoints; l++) {
            double udotc = (ux[idx] * cix[l] + uy[idx] * ciy[l] + uz[idx] * ciz[l]) / cssq;
            double feq = w_g[l] * phi[idx] * (1 + udotc);
            double Hi = sharp_c * phi[idx] * (1 - phi[idx]) * (cix[l] * normx[idx] + ciy[l] * normy[idx] + ciz[l] * normz[idx]); 
            g[F_IDX(i,j,k,l)] = feq + w_g[l] * Hi;
        }

    }
}

