function [volout] = deskewRotateFrame3D(vol, angle, dz, xyPixelSize, varargin)
% Applies a shear transform to convert raw light sheet microscopy data
% into a volume with real-world coordinates. After deskew, rotate the view of
% the volume, followed by resampling (optional). 
% 
% Based on deskewFrame3D.m and rotateFrame3D.m, and also add resampling step.
% 
% Author: Xiongtao Ruan (10/08/2020)

% xruan (02/10/2021): add option to directly apply combined processing when x step size 
% is small, and use separate processing when x step size is large (also split to
% parts in the processing when the image is tall. 
% xruan (03/16/2021): change default xStepThresh to 2.35 (ds=0.3). 
% xruan (01/27/2022): change default xStepThresh to 2.74 (ds=0.35). 
% xruan (05/26/2022): change default xStepThresh to 2.42 (ds=0.31). 
% xruan (05/30/2022): add skewed space interpolation based dsr for large step size
% xruan (06/02/2022): change default xStepThresh to 1.96 (ds=0.25). 
% xruan (07/17/2022): change default xStepThresh to 2.00 (ds=0.255). 
% xruan (10/29/2022): refactor code to first decide whether interpolate in skewed space 
% xruan (08/02/2023): add support for direct bounding box crop of output


ip = inputParser;
ip.CaseSensitive = false;
ip.addRequired('vol');
ip.addRequired('angle'); % typical value: 32.8
ip.addRequired('dz'); % typical value: 0.2-0.5
ip.addRequired('xyPixelSize'); % typical value: 0.1
ip.addParameter('reverse', false, @islogical);
ip.addParameter('Crop', true, @islogical);
ip.addParameter('bbox', [], @isnumeric);
ip.addParameter('objectiveScan', false, @islogical);
ip.addParameter('xStepThresh', 2.0, @isnumeric); % 2.344 for ds=0.3, 2.735 for ds=0.35
ip.addParameter('resampleFactor', [], @isnumeric); % resample factor in xyz order. 
ip.addParameter('gpuProcess', false, @islogical); % use gpu for the processing. 
ip.addParameter('interpMethod', 'linear', @(x) any(strcmpi(x, {'cubic', 'linear'})));
ip.parse(vol, angle, dz, xyPixelSize, varargin{:});

pr = ip.Results;
Reverse = pr.reverse;
bbox = pr.bbox;
objectiveScan = pr.objectiveScan;
xStepThresh = pr.xStepThresh;
resampleFactor = pr.resampleFactor;
gpuProcess = pr.gpuProcess;
interpMethod = pr.interpMethod;

[ny,nx,nz] = size(vol);


theta = angle * pi/180;
dx = cos(theta)*dz/xyPixelSize; % pixels shifted slice to slice in x

if ip.Results.objectiveScan
    zAniso = dz / xyPixelSize;
else
    zAniso = sin(abs(theta)) * dz / xyPixelSize;
end

% use original dz to decide outSize
if ~objectiveScan
    % outSize = round([ny nxDs/cos(theta) h]);
    % calculate height; first & last 2 frames have interpolation artifacts
    outSize = round([ny, (nx-1)*cos(theta)+(nz-1)*zAniso/sin(abs(theta)), (nx-1)*sin(abs(theta))-4]);
else
    % exact proportions of rotated box
    outSize = round([ny, nx*cos(theta)+nz*zAniso*sin(abs(theta)), nz*zAniso*cos(theta)+nx*sin(abs(theta))]);
end

%% skew space interpolation
if ~objectiveScan && abs(dx) > xStepThresh
    % skewed space interplation combined dsr
    fprintf('The step size is greater than the threshold, use skewed space interpolation for combined deskew rotate...\n');
    % for dx only slightly larger than xStepThresh, we interpolate to
    % a step size lower than the threshold, and the ratio between dz /
    % dzout ceils to the faction of 1/n with 10% to the threshold.
    if abs(dx) / xStepThresh < 1.5
        % dzout = xyPixelSize / sin(theta);
        dzout_thresh = xyPixelSize * xStepThresh / cos(theta);
        dzout = dz / (ceil((dz / dzout_thresh) / (1 / 2)) *(1 / 2));
        counter = 1;
        while dzout / dzout_thresh < 0.95
            dzout = dz / (ceil((dz / dzout_thresh) / (1 / (counter + 2))) *(1 / (counter + 2)));
            counter = counter + 1;
        end
        % round it by the significant digits of dz
        % sf = 10^floor(log10(dz));
        % dzout = round(dzout / sf ) * sf;
    else
        ndiv = ceil(abs(dx) / xStepThresh);
        dzout = dz / ndiv;
    end
    int_stepsize = dzout / dz;
    fprintf('Input dz: %f , interpolated dz: %f\n', dz, dzout);

    % add the mex version skewed space interpolation as default
    try 
        vol_1 = skewed_space_interp_defined_stepsize_mex(vol, abs(dx), int_stepsize, Reverse);
    catch ME
        disp(ME);
        vol_1 = skewed_space_interp_defined_stepsize(vol, abs(dx), int_stepsize, 'Reverse', Reverse);
    end
    
    % update parameters after interpolation
    [ny,nx,nz] = size(vol_1);
    dz = dzout;
    dx = cos(theta)*dz/xyPixelSize; % pixels shifted slice to slice in x

    if ip.Results.objectiveScan
        zAniso = dz / xyPixelSize;
    else
        zAniso = sin(abs(theta)) * dz / xyPixelSize;
    end
else
    vol_1 = vol;
end

%% deskew
if ~Reverse
    xshift = -dx;
    xstep = dx;
else
    xshift = dx + ceil((nz-1)*dx);
    xstep = -dx;
end
nxDs = ceil((nz-1)*dx) + nx; % width of output volume as if there is DS.

% shear transform matrix
if objectiveScan
    nxDs = nx;
    ds_S = eye(4);
else
    ds_S = [1 0 0 0;
            0 1 0 0;
            xstep 0 1 0;
            xshift 0 0 1];
end

%% rotate
% nxDs = nxOut;
if Reverse
    theta = -theta;
end

center = ([ny nxDs nz]+1)/2;
T1 = [1 0 0 0
      0 1 0 0
      0 0 1 0
      -center([2 1 3]) 1];

S = [1 0 0 0
     0 1 0 0
     0 0 zAniso 0
     0 0 0 1];

% Rotate x,z
R = [cos(theta) 0 -sin(theta) 0; % order for imwarp is x,y,z
     0 1 0 0;
     sin(theta) 0 cos(theta) 0;
     0 0 0 1];

T2 = [1 0 0 0
      0 1 0 0
      0 0 1 0
      (outSize([2 1 3])+1)/2 1];

%% resampling after deskew and rotate
rs = resampleFactor;
if ~isempty(rs)
    RT1 = [1 0 0 0
           0 1 0 0
           0 0 1 0
           -(outSize([2,1,3])+1)/2 1];
    RS =[1/rs(1) 0 0 0
         0 1/rs(2) 0 0
         0 0 1/rs(3) 0
         0 0 0 1];
    outSize = round(outSize ./ rs([2,1,3]));
    RT2 = [1 0 0 0
           0 1 0 0
           0 0 1 0
           (outSize([2,1,3])+1)/2 1];     
else
    RT1 = eye(4);
    RS = eye(4);
    RT2 = eye(4);
end

%% summarized transform
RA = imref3d(outSize, 1, 1, 1);
if ~isempty(bbox)
    RA = imref3d(bbox(4 : 6) - bbox(1 : 3) + 1, [bbox(2) - 0.5, bbox(5) + 0.5], [bbox(1) - 0.5, bbox(4) + 0.5], [bbox(3) - 0.5, bbox(6) + 0.5]);
end
if gpuProcess
    vol_1 = gpuArray(vol_1);
end

if gpuProcess || (~isempty(rs) && any(rs ~= 1))
    [volout] = imwarp(vol_1, affine3d(ds_S*(T1*S*R*T2)*(RT1*RS*RT2)), interpMethod, 'FillValues', 0, 'OutputView', RA);
else    
    try 
        % convert the transformation matrix to backward and the form for c/c++
        offset = zeros(4, 4);
        offset(4, 1 : 3) = 1;
        if ~objectiveScan && Reverse
            ds_S(4, 1) = ds_S(4, 1) - dx;
        end
        tmat = eye(4) / (ds_S*((T1+offset)*S*R*(T2-offset))*(RT1*RS*RT2))';
        tmat = tmat([2, 1, 3, 4], [2, 1, 3, 4]);

        if ~isempty(bbox)
            volout = volume_deskew_rotate_warp_mex(vol_1, tmat, bbox);
        else
            volout = volume_deskew_rotate_warp_mex(vol_1, tmat, [1, 1, 1, outSize]);
        end
    catch ME
        disp(ME);
        [volout] = imwarp(vol_1, affine3d(ds_S*(T1*S*R*T2)*(RT1*RS*RT2)), interpMethod, 'FillValues', 0, 'OutputView', RA);
    end
end
if gpuProcess
    volout = gather(volout);
end

end


