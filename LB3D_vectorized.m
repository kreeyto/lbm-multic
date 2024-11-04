%% D3Q19 
clc; clearvars; close all

%% Parâmetros Gerais

slicebool = 2;
nlinks = 19;
tau = 0.8;
cssq = 1/3;
omega = 1/tau;
sharp_c = 0.1;
sigma = 0.024;

[nx, ny, nz] = deal(50);
nsteps = 20000; 

gpoints = 15;
f = zeros(nx,ny,nz,19); 
g = zeros(nx,ny,nz,gpoints); 

%% Matrizes e Variáveis

[rho, u, v, w, ...
 fi, normx, normy, normz, ...
 curvature, indicator, ...
 ffx, ffy, ffz, ...
 mod_grad, isfluid] = deal(zeros(nx,ny,nz));

[pxx, pyy, pzz, ...
 pxy, pxz, pyz] = deal(ones(nx,ny,nz));

p = zeros(1,19);
p_g = zeros(1,gpoints);

fneq = zeros(19,1,1);
isfluid(2:nx-1,2:ny-1,2:nz-1) = 1;
rho(:,:,:) = 1;

%% Propriedades do Modelo

p(1) = 1/3;
p(2:6) = 1/18;
p(7:19) = 1/36;

p_g(1) = 2/9;
p_g(2:7) = 1/9;
p_g(8:15) = 1/72;

ex = [0, 1, -1, 0, 0, 0, 0, 1, -1, 1, -1, 0, 0, 1, -1, 1, -1, 0, 0];
ey = [0, 0, 0, 1, -1, 0, 0, 1, -1, 0, 0, 1, -1, -1, 1, 0, 0, 1, -1];
ez = [0, 0, 0, 0, 0, 1, -1, 0, 0, 1, -1, 1, -1, 0, 0, -1, 1, -1, 1];

%% Cálculo da Função de Distribuição em Função da Distância Radial

for i = 1:nx
    for j = 1:ny
        for k = 1:nz
            Ri = sqrt((i - nx/2)^2 + (j - ny/2)^2 + (k - nz/2)^2);
            fi(i,j,k) = 0.5 + 0.5 * tanh(10*(20-Ri)/3);
        end
    end
end

%% Inicialização de Funções de Distribuição

for i = 1:19
    f(:,:,:,i) = p(i) * rho(:,:,:);
end

for i = 1:gpoints
    g(:,:,:,i) = p_g(i) * fi(:,:,:);
end

%% Loop de Simulação

for t = 1:nsteps

    % Campo de fase
    fi = sum(g, 4);

    % Normal e arrays
    [grad_fix, grad_fiy, grad_fiz] = deal(zeros(nx, ny, nz));
    for l = 1:19
        grad_fix = grad_fix + 3 * p(l) .* ex(l) .* circshift(fi,[-ex(l),-ey(l),-ez(l)]);
        grad_fiy = grad_fiy + 3 * p(l) .* ey(l) .* circshift(fi,[-ex(l),-ey(l),-ez(l)]);
        grad_fiz = grad_fiz + 3 * p(l) .* ez(l) .* circshift(fi,[-ex(l),-ey(l),-ez(l)]);
    end
    mod_grad = sqrt(grad_fix.^2 + grad_fiy.^2 + grad_fiz.^2) + 1e-9;
    normx = grad_fix ./ mod_grad;
    normy = grad_fiy ./ mod_grad;
    normz = grad_fiz ./ mod_grad;
    indicator = mod_grad;

    % Curvatura e forças de tensão superficial
    curvature = zeros(nx, ny, nz);
    for l = 1:19
        circnormx = circshift(normx,[-ex(l),-ey(l),-ez(l)]);
        circnormy = circshift(normy,[-ex(l),-ey(l),-ez(l)]);
        circnormz = circshift(normz,[-ex(l),-ey(l),-ez(l)]);
        curvature = curvature - 3 * p(l) .* (ex(l) .* circnormx + ey(l) .* circnormy + ez(l) .* circnormz);
    end
    ffx = sigma .* curvature .* normx .* indicator;
    ffy = sigma .* curvature .* normy .* indicator;
    ffz = sigma .* curvature .* normz .* indicator;

    % Momentos
    rho = sum(f, 4);
    
    u = sum(f(:,:,:, [2, 16, 10, 8, 14]), 4) - sum(f(:,:,:, [3, 11, 17, 15, 9]), 4);
    v = sum(f(:,:,:, [4, 8, 15, 18, 12]), 4) - sum(f(:,:,:, [5, 14, 9, 13, 19]), 4);
    w = sum(f(:,:,:, [7, 16, 11, 18, 13]), 4) - sum(f(:,:,:, [6, 10, 17, 12, 19]), 4);

    u = u ./ rho + ffx * 0.5 ./ rho;
    v = v ./ rho + ffy * 0.5 ./ rho;
    w = w ./ rho + ffz * 0.5 ./ rho;
 
    uu = 0.5 * (u.^2 + v.^2 + w.^2) / cssq;
    
    [pxx, pyy, pzz, pxy, pxz, pyz] = deal(zeros(nx,ny,nz));
    for l = 1:19
        udotc = (u * ex(l) + v * ey(l) + w * ez(l)) / cssq;
        HeF = (p(l) * (rho + rho .* (udotc + 0.5 .* udotc.^2 - uu))) ...
                .* ((ex(l) - u) .* ffx + ...
                    (ey(l) - v) .* ffy + ...
                    (ez(l) - w) .* ffz ...
                   ) ./ (rho .* cssq);
        feq = p(l) * (rho + rho .* (udotc + 0.5 .* udotc.^2 - uu)) - 0.5 .* HeF;
        fneq = f(:,:,:,l) - feq;        
    end

    pxx = sum(fneq([2, 3, 8, 9, 10, 11, 14, 15, 16, 17]));
    pyy = sum(fneq([4, 5, 8, 9, 12, 13, 14, 15, 18, 19]));
    pzz = sum(fneq([6, 7, 10, 11, 12, 13, 16, 17, 18, 19]));
    pxy = sum(fneq([8, 9])) - sum(fneq([14, 15]));
    pxz = sum(fneq([10, 11])) - sum(fneq([16, 17]));
    pyz = sum(fneq([12, 13])) - sum(fneq([18, 19]));

    % Colisão
    for l = 1:19
        udotc = (u * ex(l) + v * ey(l) + w * ez(l)) / cssq;
        feq = p(l) * (rho + rho .* (udotc + 0.5 .* udotc.^2 - uu));
        HeF = 0.5 * (p(l) * (rho + rho .* (udotc + 0.5 .* udotc.^2 - uu))) ...
                .* ((ex(l) - u) .* ffx + ...
                    (ey(l) - v) .* ffy + ...
                    (ez(l) - w) .* ffz ...
                   ) ./ (rho .* cssq);
        fneq = (ex(l) .* ex(l) - cssq) * pxx + ...
               (ey(l) .* ey(l) - cssq) * pyy + ...
               (ez(l) .* ez(l) - cssq) * pzz + ...
                2 * ex(l) .* ey(l) .* pxy + ...
                2 * ex(l) .* ez(l) .* pxz + ...
                2 * ey(l) .* ez(l) .* pyz;
        fcirc = feq + (1-omega) * (p(l) / (2*cssq^2)) * fneq + HeF;
        f(:,:,:,l) = circshift(fcirc, [ex(l), ey(l), ez(l)]);
    end
    for l = 1:gpoints
        udotc = (u * ex(l) + v * ey(l) + w * ez(l)) / cssq;
        feq = p_g(l) .* fi .* (1 + udotc);
        Hi = sharp_c .* fi .* (1 - fi) .* (ex(l) .* normx + ey(l) .* normy + ez(l) .* normz); 
        g(:,:,:,l) = feq + p_g(l) .* Hi;
    end    

    % Streaming 
    for l = 1:gpoints
        g(:,:,:,l) = circshift(g(:,:,:,l),[ex(l),ey(l),ez(l),0]);
    end

    % Condições de contorno
    %{
    for l = 1:19
        f(:,:,:,l) = circshift(rho .* p(l),[ex(l),ey(l),ez(l)]);
    end
    for l = 1:gpoints
        g(:,:,:,l) = circshift(fi .* p_g(l),[ex(l),ey(l),ez(l)]);
    end
    %}

    for i = 1:nx
        for j = 1:ny
            for k = 1:nz
                if isfluid(i,j,k) == 1
                    for l = 1:19
                        if (i + ex(l) > 0 && j + ey(l) > 0 && k + ez(l) > 0)
                            f(i + ex(l), j + ey(l), k + ez(l), l) = rho(i,j,k) .* p(l); 
                        end
                    end
                    for l = 1:gpoints
                        if (i + ex(l) > 0 && j + ey(l) > 0 && k + ez(l) > 0)
                            g(i + ex(l), j + ey(l), k + ez(l), l) = fi(i,j,k) .* p_g(l);
                        end
                    end
                end
            end
        end
    end
    
    fi(:, :, 1) = fi(:, :, 2);  
    fi(:, :, nz) = fi(:, :, nz-1); 
    fi(1, :, :) = fi(2, :, :); 
    fi(nx, :, :) = fi(nx-1, :, :); 
    fi(:, 1, :) = fi(:, 2, :); 
    fi(:, ny, :) = fi(:, ny-1, :); 

    % Visualização 
    if mod(t, 1) == 0
        if slicebool == 1
            hFig = figure(1); clf;
            x = 1:nx; y = 1:ny; z = 1:nz;
            h = slice(x, y, z, fi, [], ny/2, []); 
            shading interp; colorbar; 
            xlabel('X'); ylabel('Y'); zlabel('Z'); 
            title(['t = ', num2str(t)]);
            view(3); drawnow; 
        else
            hFig = figure(1); clf;
            x = 1:nx; y = 1:ny; z = 1:nz;
            surfpatch = patch(isosurface(x, y, z, fi, 0.5));
            set(surfpatch, 'FaceColor', 'red', 'EdgeColor', 'none'); 
            xlabel('X'); ylabel('Y'); zlabel('Z');
            axis([1 nx 1 ny 1 nz]);
            axis equal;
            camlight; lighting phong; 
            title(['t = ', num2str(t)]);
            view(3); drawnow;
        end
    end

    disp(['Passo de tempo: ', num2str(t)]);
end
