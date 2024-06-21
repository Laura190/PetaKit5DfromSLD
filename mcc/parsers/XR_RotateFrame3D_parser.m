function [] = XR_RotateFrame3D_parser(framePaths, xyPixelSize, dz, varargin)


ip = inputParser;
ip.CaseSensitive = false;
ip.addRequired('framePaths', @(x) ischar(x) || iscell(x)); 
ip.addRequired('xyPixelSize', @(x) isscalar(x) || ischar(x)); 
ip.addRequired('dz', @(x) isscalar(x) || ischar(x)); 
ip.addParameter('objectiveScan', false, @(x) islogical(x) || ischar(x));
ip.addParameter('Overwrite', false, @(x) islogical(x) || ischar(x));
ip.addParameter('Crop', true, @(x) islogical(x) || ischar(x));
ip.addParameter('bbox', [], @(x) isnumeric(x) || ischar(x));
ip.addParameter('resample', [], @(x) isnumeric(x) || ischar(x)); % resampling after rotation 
ip.addParameter('SkewAngle', 31.5, @(x) isscalar(x) || ischar(x));
ip.addParameter('Reverse', false, @(x) islogical(x) || ischar(x));
ip.addParameter('sCMOSCameraFlip', false, @(x) islogical(x) || ischar(x));
ip.addParameter('save16bit', true , @(x) islogical(x) || ischar(x)); % saves deskewed data as 16 bit -- not for quantification
ip.addParameter('uuid', '', @ischar);

ip.parse(framePaths, xyPixelSize, dz, varargin{:});

pr = ip.Results;
objectiveScan = pr.objectiveScan;
Overwrite = pr.Overwrite;
Crop = pr.Crop;
bbox = pr.bbox;
resample = pr.resample;
SkewAngle = pr.SkewAngle;
Reverse = pr.Reverse;
sCMOSCameraFlip = pr.sCMOSCameraFlip;
save16bit = pr.save16bit;
uuid = pr.uuid;

if ischar(framePaths) && ~isempty(framePaths) && strcmp(framePaths(1), '{')
    framePaths = eval(framePaths);
end
if ischar(xyPixelSize)
    xyPixelSize = str2num(xyPixelSize);
end
if ischar(dz)
    dz = str2num(dz);
end
if ischar(objectiveScan)
    objectiveScan = str2num(objectiveScan);
end
if ischar(Overwrite)
    Overwrite = str2num(Overwrite);
end
if ischar(Crop)
    Crop = str2num(Crop);
end
if ischar(bbox)
    bbox = str2num(bbox);
end
if ischar(resample)
    resample = str2num(resample);
end
if ischar(SkewAngle)
    SkewAngle = str2num(SkewAngle);
end
if ischar(Reverse)
    Reverse = str2num(Reverse);
end
if ischar(sCMOSCameraFlip)
    sCMOSCameraFlip = str2num(sCMOSCameraFlip);
end
if ischar(save16bit)
    save16bit = str2num(save16bit);
end

XR_RotateFrame3D(framePaths, xyPixelSize, dz, objectiveScan=objectiveScan, ...
    Overwrite=Overwrite, Crop=Crop, bbox=bbox, resample=resample, SkewAngle=SkewAngle, ...
    Reverse=Reverse, sCMOSCameraFlip=sCMOSCameraFlip, save16bit=save16bit, ...
    uuid=uuid);

end

