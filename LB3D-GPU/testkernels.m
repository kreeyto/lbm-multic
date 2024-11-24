clc; clearvars; close all

% parameters

radius = 20;
cssq = gpuArray(1/3);
sigma = 0.1;

[nx, ny, nz] = deal(128);

% kernels

ker = parallel.gpu.CUDAKernel('myKernel.ptx', 'myKernel.cu', 'momCollision');
ker.ThreadBlockSize = [8, 8, 8];
ker.GridSize = [ceil(nx/8), ceil(ny/8), ceil(nz/8)]; 

nx_gpu = gpuArray(nx); ny_gpu = gpuArray(ny); nz_gpu = gpuArray(nz);

% remaining pars

nsteps = 10000; 

fpoints = gpuArray(19); 
gpoints = 15;
f = zeros(nx,ny,nz,fpoints,'gpuArray'); 
g = zeros(nx,ny,nz,gpoints); 

% index pre-alloc

ix = 2:nx-1; iy = 2:ny-1; iz = 2:nz-1;

% arrays and variables

[rho, ux, uy, uz, ...
 ffx, ffy, ffz] = deal(zeros(nx,ny,nz,'gpuArray'));

[phi, normx, normy, normz, ...
 curvature, indicator] = deal(zeros(nx,ny,nz));

[pxx, pyy, pzz, ...
 pxy, pxz, pyz] = deal(ones(nx,ny,nz,'gpuArray'));

w = zeros(1,fpoints,'gpuArray');
w_g = zeros(1,gpoints);
rho(:,:,:) = 1;

% velocity set properties

w(1) = 1/3;
w(2:6) = 1/18;
w(7:19) = 1/36;

w_g(1) = 2/9;
w_g(2:7) = 1/9;
w_g(8:15) = 1/72;

cix = gpuArray([0, 1, -1, 0, 0, 0, 0, 1, -1, 1, -1, 0, 0, 1, -1, 1, -1, 0, 0]);
ciy = gpuArray([0, 0, 0, 1, -1, 0, 0, 1, -1, 0, 0, 1, -1, -1, 1, 0, 0, 1, -1]);
ciz = gpuArray([0, 0, 0, 0, 0, 1, -1, 0, 0, 1, -1, 1, -1, 0, 0, -1, 1, -1, 1]);

% phase field init

nx2 = nx/2; ny2 = ny/2; nz2 = nz/2; 
for i = ix
    for j = iy
        for k = iz
            Ri = sqrt((i-nx2)^2/2.^2 + (j-ny2)^2 + (k-nz2)^2);
            phi(i,j,k) = 0.5 + 0.5 * tanh(2*(radius-Ri)/3);
        end
    end
end

% distribution function init

for i = 1:fpoints
    f(:,:,:,i) = w(i) * rho(:,:,:);
end

for i = 1:gpoints
    g(:,:,:,i) = w_g(i) * phi(:,:,:);
end

% simulation loop
% beware of kernel calling inside loop, may cause malfunction

% phase field calc
phi(ix,iy,iz) = sum(g(ix,iy,iz,:),4);

% normal and arrays
[grad_fix, grad_fiy, grad_fiz] = deal(0);
for l = 1:fpoints
    grad_fix = grad_fix + 3 * w(l) .* cix(l) .* ((phi((ix)+cix(l),(iy)+ciy(l),(iz)+ciz(l))));
    grad_fiy = grad_fiy + 3 * w(l) .* ciy(l) .* ((phi((ix)+cix(l),(iy)+ciy(l),(iz)+ciz(l))));
    grad_fiz = grad_fiz + 3 * w(l) .* ciz(l) .* ((phi((ix)+cix(l),(iy)+ciy(l),(iz)+ciz(l))));
end
mod_grad(ix,iy,iz) = sqrt(grad_fix.^2 + grad_fiy.^2 + grad_fiz.^2);
normx(ix,iy,iz) = grad_fix ./ (mod_grad(ix,iy,iz) + 1e-9);
normy(ix,iy,iz) = grad_fiy ./ (mod_grad(ix,iy,iz) + 1e-9);
normz(ix,iy,iz) = grad_fiz ./ (mod_grad(ix,iy,iz) + 1e-9);
indicator(ix,iy,iz) = sqrt(grad_fix.^2 + grad_fiy.^2 + grad_fiz.^2);

% curvature
curvature(ix,iy,iz) = 0;
for l = 1:fpoints
    curvature(ix,iy,iz) = curvature(ix,iy,iz) - 3 .* w(l) .* ...
    (cix(l) .* (normx((ix)+cix(l),(iy)+ciy(l),(iz)+ciz(l))) + ...
     ciy(l) .* (normy((ix)+cix(l),(iy)+ciy(l),(iz)+ciz(l))) + ...
     ciz(l) .* (normz((ix)+cix(l),(iy)+ciy(l),(iz)+ciz(l))) ...
    );
end
ffx(ix,iy,iz) = sigma .* curvature(ix,iy,iz) .* normx(ix,iy,iz) .* indicator(ix,iy,iz);
ffy(ix,iy,iz) = sigma .* curvature(ix,iy,iz) .* normy(ix,iy,iz) .* indicator(ix,iy,iz);
ffz(ix,iy,iz) = sigma .* curvature(ix,iy,iz) .* normz(ix,iy,iz) .* indicator(ix,iy,iz);

output = feval(ker, ...
               rho, ux, uy, uz, ...
               ffx, ffy, ffz, f, ...
               nx_gpu, ny_gpu, nz_gpu, ...
               cssq, cix, ciy, ciz, w, ...
               pxx, pyy, pzz, pxy, pxz, pyz, ...
               fpoints);

