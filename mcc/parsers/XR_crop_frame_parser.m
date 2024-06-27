function [] = XR_crop_frame_parser(dataFullpath, saveFullpath, bbox, varargin)


ip = inputParser;
ip.CaseSensitive = false;
ip.addRequired('dataFullpath', @(x) ischar(x) || iscell(x));
ip.addRequired('saveFullpath', @(x) ischar(x) || iscell(x));
ip.addRequired('bbox', @(x) isnumeric(x) || ischar(x));
ip.addParameter('overwrite', false, @(x) islogical(x) || ischar(x)); % start coordinate of the last time point
ip.addParameter('pad', false, @(x) islogical(x) || ischar(x)); % pad region that is outside the bbox
ip.addParameter('zarrFile', false , @(x) islogical(x) || ischar(x)); % read zarr
ip.addParameter('largeFile', false, @(x) islogical(x) || ischar(x)); % use zarr file as input
ip.addParameter('saveZarr', false , @(x) islogical(x) || ischar(x)); % save as zarr
ip.addParameter('batchSize', [1024, 1024, 1024] , @(x) isnumeric(x) || ischar(x));
ip.addParameter('blockSize', [256, 256, 256] , @(x) isnumeric(x) || ischar(x));
ip.addParameter('uuid', '', @ischar);
ip.addParameter('parseCluster', true, @(x) islogical(x) || ischar(x));
ip.addParameter('mccMode', false, @(x) islogical(x) || ischar(x));
ip.addParameter('configFile', '', @ischar);

ip.parse(dataFullpath, saveFullpath, bbox, varargin{:});

pr = ip.Results;
overwrite = pr.overwrite;
pad = pr.pad;
zarrFile = pr.zarrFile;
largeFile = pr.largeFile;
saveZarr = pr.saveZarr;
batchSize = pr.batchSize;
blockSize = pr.blockSize;
uuid = pr.uuid;
parseCluster = pr.parseCluster;
mccMode = pr.mccMode;
configFile = pr.configFile;

if ischar(dataFullpath) && ~isempty(dataFullpath) && strcmp(dataFullpath(1), '{')
    dataFullpath = eval(dataFullpath);
end
if ischar(saveFullpath) && ~isempty(saveFullpath) && strcmp(saveFullpath(1), '{')
    saveFullpath = eval(saveFullpath);
end
if ischar(bbox)
    bbox = str2num(bbox);
end
if ischar(overwrite)
    overwrite = str2num(overwrite);
end
if ischar(pad)
    pad = str2num(pad);
end
if ischar(zarrFile)
    zarrFile = str2num(zarrFile);
end
if ischar(largeFile)
    largeFile = str2num(largeFile);
end
if ischar(saveZarr)
    saveZarr = str2num(saveZarr);
end
if ischar(batchSize)
    batchSize = str2num(batchSize);
end
if ischar(blockSize)
    blockSize = str2num(blockSize);
end
if ischar(parseCluster)
    parseCluster = str2num(parseCluster);
end
if ischar(mccMode)
    mccMode = str2num(mccMode);
end

XR_crop_frame(dataFullpath, saveFullpath, bbox, overwrite=overwrite, pad=pad, ...
    zarrFile=zarrFile, largeFile=largeFile, saveZarr=saveZarr, batchSize=batchSize, ...
    blockSize=blockSize, uuid=uuid, parseCluster=parseCluster, mccMode=mccMode, ...
    configFile=configFile);

end

