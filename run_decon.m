% Devonvolves LLSM 3i Slidebook (.sld) or Zeiss files (.czi) using PetaKit5D (formely known as
% llsm5dtools), followed by deskewing, and finally saving as .tif files and maximum intensity projections. 
% Petakit5d doesn't accept .sld or .czi files so firstly these are converted to .tif. 

% Requires installing PetaKit5D (not the GUI version) and adding it to the matlab path 
% Installation instructions with the required matlab toolboxes are on their github:
% https://github.com/abcucberkeley/PetaKit5D

% Requires a modified Matlab bioformats toolbox to read in .sld files and
% adding it to the Matlab path.
% Possibly requires removing the bioformats that's included with petakit5d?
% This will be available somewhere like the CAMDU github

% Requires a PSF for each channel in .tif format (not .tiff).
% All the .sld or .czi files in that folder will be processed with the same PSF.

% TODO: Make it so that if its 2D it skips the series

% Folder containing the .sld files to be processed.
% Don't use "C0" or "C1" in the .sld filenames or anywhere in the pathname,
% otherwise it'll break. Folder path needs to end in \
% Ask the user to select a folder first
[inputFolder, filePaths]=inputSelector();

% Name of the PSF files.
% Must be .tif format and placed in the same folder as the .sld or .czi files.
% The PSF must have the same slice spacing as the image (e.g. 0.5um). 
% The metadata probably needs to be correct for the XYZ pixel spacing (e.g. 0.104 um for XY and 0.5 um for Z). 

% PSF_C0 = 'PSF BW 647.tif';
%PSF_C1 = '560_PSF.tif';

% PSF_C0 = 'PSF_488.tif';
% PSF_C1 = 'PSF_640.tif';

% if ~isfile([inputFolder PSF_C0])
%     error('File does not exist: %s', PSF_C0);
% end
% if exist('PSF_C1','var') == 1 && ~isfile([inputFolder PSF_C1])
%     error('File does not exist: %s', PSF_C1);
% end

for i=1:length(filePaths)
    if ~isfile(filePaths{i})
        error('File does not exist: %s', filePaths{i});
    end
end

% z step size
dz = 1;

% Change below to 'mirror' if you get edge artefacts with deconvolution.
% For our purposes you don't need this unless you have signal in the first or last few slices of the stack.
% Use a z_padding number that is half the number of slices in the stack, or fewer. And at least 5.
% E.g. if you stack is 40 slices, then use 20.
% Options: 'none', 'zero', 'mirror', 'gaussian', 'fixed'
z_edge_padding = 'none'; % Set default or input value
z_padding = 10; % Default value
 
% Predefine parameters for Gaussian and fixed padding
gaussian_mean = 102.27; % Mean for Gaussian sampling
gaussian_std = 3.17; % Standard deviation for Gaussian sampling
fixed_value = 100; % Value for fixed padding

%disable MIPS after decon, only want them after deskew
% can we output to a different directory to the tifs?
% can we delete the intermediate tifs?

% For 2024a it now uses the GPU, had to update graphics driver for matlab
% to recognise GPU, this takes a lot of pressure off of the 
% CPU, The decon is still relatively slow but has low GPU utilisation, if
% we calculate the size of each slice and how much expected GPU we can cut
% up the time points in order to parallelise the process on the GPU, expect
% 10-20x speed up so worth the time

% Choose a deconvolution method. Either 'omw' or the standard matlab richardson lucy 'simplified'. 
RLmethod = 'simplified';
% number of iterations for deconvolution. For omw use 2 iterations.
DeconIter = 1;
% Wiener filter parameter for OMW deconvolution method
% alpha parameter should be adjusted based on SNR and data quality.
% typically 0.002 - 0.01 for SNR ~20; 0.02 - 0.1 or higher for SNR ~7
wienerAlpha = 0.05;

% Delete the raw .tif (i.e. the ones that aren't deconvolved or deskewed
deleteRawTif = false; 
% Delete the .tif files that are deconvolved but not deskewed
deleteDeconTif = false;

%% Preset Parameters 
% Deconvolution parameters 
% add the software to the path not working 
% setup([]);

% xy pixel size in um. 0.104 um for 3i LLSM, 0.1449922 for Zeiss LSM
czi_xyPixelSize = 0.1449922; %Zeiss LSM
sld_xyPixelSize = 0.104; %3i LLSM

% scan direction
Reverse = true;
% psf z step size (we assume xyPixelSize also apply to psf)
dzPSF = 0.5;

% if true, check whether image is flipped in z using the setting files
parseSettingFile = false;

% channel patterns for the channels, the channel patterns should map the
% order of PSF filenames.
ChannelPatterns = {'Ch0', ...
                   };  

% psf path
psf_rt = inputFolder;            

PSFFullpaths = filePaths;            


% OTF thresholding parameter
OTFCumThresh = 0.9;
% true if the PSF is in skew space
skewed = true;
% deconvolution result path string (within dataPath)
resultDirName = 'deconvolved';

% background to subtract
Background = 100;

% decon to 80 iterations (not use the criteria for early stop)
fixIter = true;
% erode the edge after decon for number of pixels.
EdgeErosion = 0;
% save as 16bit; if false, save to single
Save16bit = true;
% use zarr file as input; if false, use tiff as input
zarrFile = false;
% save output as zarr file; if false,s ave as tiff
saveZarr = false;
% number of cpu cores
cpusPerTask = 4;
% use cluster computing for different images
parseCluster = false;
% set it to true for large files that cannot be fitted to RAM/GPU, it will
% split the data to chunks for deconvolution
largeFile = false;
% use GPU for deconvolution
GPUJob = true;
% if true, save intermediate results every 5 iterations.
debug = false;
% config file for the master jobs that runs on CPU node
ConfigFile = '';
% config file for the GPU job scheduling on GPU node
GPUConfigFile = '';
% if true, use Matlab runtime (for the situation without matlab license)
mccMode = false;


% Deskew parameters


% also do coverslip correction rotation (usually at Warwick we don't do this)
rotate = false;
% skew angle, this is 32.8 for the 3i LLSM, and 30 for the Zeiss LLSM
czi_skewAngle = 32.8; %Zeiss LLSM
sld_skewAngle = 30; %3i LLSM


% flipZstack, this is true for the 3i LLSM, and false for the Zeiss LLSM
czi_flipZstack = false;
sld_flipZstack = true;
% not sure this is necessary when we aren't rotating
DSRCombined = false;
% true if input is in Zarr format
zarrFile = false;
% true if saving result as Zarr files
saveZarr = false;
% true if saving result as Uint16
Save16bit = true;
% save intermediate iteration results (only for simplified, not for omw)
saveStep = false;

% use slurm cluster if true, otherwise use the local machine (master job)
parseCluster = false;
% use master job for task computing or not. 
masterCompute = true;
% configuration file for job submission
configFile = '';
% if true, use Matlab runtime (for the situation without matlab license)
mccMode = false;


%% Step 1. Convert the .sld files into .tif files

% Find "czi" or "sld" files in directory. All files assumed to be one or
% the other
llsmType = "czi"; 
filePattern = fullfile(inputFolder, strcat('*.', llsmType)); 
theFiles = dir(filePattern);
xyPixelSize = czi_xyPixelSize;
skewAngle = czi_skewAngle;
flipZstack = czi_flipZstack;
%if no czi files found look for slds
if isempty(theFiles)
    llsmType = "sld";
    filePattern = fullfile(inputFolder, strcat('*.', llsmType)); 
    theFiles = dir(filePattern);
    xyPixelSize = sld_xyPixelSize;
    skewAngle = sld_skewAngle;
    flipZstack = sld_flipZstack;
end
radians = deg2rad(skewAngle);
% Calculate the sine of the angle in radians
sine_value = sin(radians);

%If not sld or czi files found, exit the script
if isempty(theFiles)
    fprintf("No .czi or .sld files found. Exiting script.\n");
    return;
end

% Store total number of files to study
nFiles = length(theFiles);

% Iterate through all the .sld or .czi files in the directory
for k = 1:nFiles
    fprintf("   >> Converting .%s to tif: %3d / %3d\n", llsmType, k, nFiles);

    % Define full file name for current loop iteration
    baseFileName = theFiles(k).name;
    fullFileName = fullfile(theFiles(k).folder, baseFileName)

    r = bfGetReader(fullFileName);

    %access the OME metadata and get number of series
    omeMeta = r.getMetadataStore();
    nSeries = r.getSeriesCount();

    %Iterate through series within the file
    for S = 0:nSeries-1


        %switch between series and load that series
        r.setSeries(S);
        %r.getSeries();

        %get metadata and extract important features
        % check X and Y are correct and not switched
        omeMeta = r.getMetadataStore();
        stackSizeX = omeMeta.getPixelsSizeX(S).getValue();      %image width in pixels
        stackSizeY = omeMeta.getPixelsSizeY(S).getValue();     %image height in pixels
        stackSizeZ = omeMeta.getPixelsSizeZ(S).getValue();      %number of slices
        stackSizeC = omeMeta.getPixelsSizeC(S).getValue();      %number of channels
        stackSizeT = omeMeta.getPixelsSizeT(S).getValue();      %number of time points
        % Extract physical pixel size (XY spacing)
        pixelSizeX = omeMeta.getPixelsPhysicalSizeX(S); % in micrometers
        if ~isempty(pixelSizeX)
            pixelSizeX = double(pixelSizeX.value());  
        else
            pixelSizeX = NaN;
        end

        pixelSizeY = omeMeta.getPixelsPhysicalSizeY(S); % in micrometers
        if ~isempty(pixelSizeY)
            pixelSizeY = double(pixelSizeY.value());
        else
            pixelSizeY = NaN;
        end

        % if the images come from the zeiss lattice lightsheet (czi format) the image will rotated 90 degrees clockwise later,
        % so swap stackSizeX and stackSizeY here
        if llsmType=="czi" 
            [stackSizeX, stackSizeY] = deal(stackSizeY, stackSizeX);
        end

        % Extract Z spacing
        pixelSizeZ = omeMeta.getPixelsPhysicalSizeZ(S); % in micrometers
        if ~isempty(pixelSizeZ)
            pixelSizeZ = double(pixelSizeZ.value());
        else
            pixelSizeZ = NaN;
        end
        deskewedZSpacing = sine_value * pixelSizeZ;

        % Extract frame interval
        frameInterval = 0;
        % % Extract frame interval
        % frameInterval = omeMeta.getPixelsTimeIncrement(1); % in seconds
        % if ~isempty(frameInterval)
        %     frameInterval = frameInterval.value();
        % else
        %     frameInterval = NaN;
        % end
        if stackSizeC == 1
            PSFFullpaths = filePaths;
            ChannelPatterns = {'Ch0', ...
                   };  
        end 

        % Print extracted values
        fprintf('Stack Size (X, Y, Z, C, T): (%d, %d, %d, %d, %d)\n', stackSizeX, stackSizeY, stackSizeZ, stackSizeC, stackSizeT);
        fprintf('Pixel Size (X, Y): (%.3f, %.3f) micrometers\n', pixelSizeX, pixelSizeY);
        fprintf('Z Spacing: %.2f micrometers\n', pixelSizeZ);
        fprintf('Deskewed Z Spacing: %.3f micrometers\n', deskewedZSpacing);

        seriesName = char(omeMeta.getImageName(S));
        seriesName = strrep(seriesName, "#", "");  % Remove all '#' characters
        seriesName = strrep(seriesName, ".", "");  % Remove all '.' characters

        % Take the original image filename and the series image name and make a new
        % folder based on this
        seriesFolderName = strrep(baseFileName, strcat(".", llsmType), "");
        seriesNameNoSpaces = strrep(seriesName, " ", "_");
        currentSeriesFolder = seriesFolderName+'_'+seriesNameNoSpaces;
        mkdir(inputFolder,currentSeriesFolder);

        currentSeriesPath = fullfile(inputFolder, currentSeriesFolder);

        % make a folder to store the .tif files

        mkdir(currentSeriesPath,'tifs');
        tifDir = fullfile(currentSeriesPath,'tifs');

        %skip the series if it has only one Z-slice
        plane_count = 0;
        if stackSizeZ>1
            %We need to store all of Z-stacks of this time-point and
            %channel in an array to be processed later, so set up and empty array
            %and start a count
            count = 1;
            array = [];

            %iterate through all the timepoints
            for T = 0:stackSizeT-1
                %iterate through all the channels
                for C = 0:stackSizeC-1
                    %iterate through all the z-slices
                    for Z = 0:stackSizeZ-1

                        %Use the index to read in the specific plane and
                        %convert to double
                        plane = bfGetPlane(r, r.getIndex(Z, C, T) +1);
                        plane = double(plane);

                        % if the images come from the Zeiss LLSM then rotate the plane 90 degrees clockwise
                        % required for later deskew (and deconvolution?) steps
                        if llsmType == "czi"
                            plane = rot90(plane, -1);
                        end

                        %Add plane to array at position (count, 1)(in essence
                        %you are appending the array) and add 1 to count.
                        %Possibly this step could be improved, there's
                        %maybe a simpler way to read this without a for
                        %loop
                        array(:,:,count) = plane;
                        count = count+1;
                        plane_count = plane_count+1;

                        % this should be first of second timepoint
                        if plane_count == int32(stackSizeZ*stackSizeC)+1
                            plane_count
                            frameInterval = omeMeta.getPlaneDeltaT(S, plane_count).value().doubleValue()/1000; % in seconds
                            firstframeInterval = omeMeta.getPlaneDeltaT(S, 0).value().doubleValue()/1000; % in seconds
                            frameInterval =  frameInterval - firstframeInterval;
                        end

                    end

                    %prepare the stack array to be saved
                    outputArray = array(1:stackSizeY, 1:stackSizeX, 1:stackSizeZ);
                    outputArray = uint16(outputArray);

                    %prepare the image name
                    strSld = baseFileName(1:end-4);
                    strS = num2str(S);
                    strT = num2str(T); 
                    strT = pad(strT,4,'left','0'); % zero padding
                    strC = num2str(C);

                    % Ensure all variables are character arrays
                    tifDir = char(tifDir);
                    tifFullpath = fullfile(tifDir, [strSld '_S' strS '_T' strT '_Ch' strC '.tif']);  
                    
                    % Check the padding type and apply accordingly
                    % We should automatically turn padding off if only
                    % deskew, and no deconvolution
                    switch z_edge_padding
                        case 'none'
                            % No padding applied
                            outputArray = outputArray;
                            
                        case 'zero'
                            % Apply zero padding
                            outputArray = padarray(outputArray, [0, 0, z_padding], 0, 'both');
                            
                        case 'mirror'
                            % Apply mirror padding
                            outputArray = padarray(outputArray, [0, 0, z_padding], 'symmetric', 'both');
                            
                        case 'gaussian'
                            % Apply Gaussian sampling padding with predefined mean and standard deviation
                            frontPad = gaussian_mean + gaussian_std .* randn(size(outputArray, 1), size(outputArray, 2), z_padding);
                            backPad = gaussian_mean + gaussian_std .* randn(size(outputArray, 1), size(outputArray, 2), z_padding);
                            
                            % Concatenate the Gaussian padding to the original array
                            outputArray = cat(3, frontPad, outputArray, backPad);
                            
                        case 'fixed'
                            % Apply fixed-value padding
                            frontPad = fixed_value * ones(size(outputArray, 1), size(outputArray, 2), z_padding);
                            backPad = fixed_value * ones(size(outputArray, 1), size(outputArray, 2), z_padding);
                            
                            % Concatenate the fixed padding to the original array
                            outputArray = cat(3, frontPad, outputArray, backPad);
                            
                        otherwise
                            error('Invalid z_edge_padding option. Choose ''none'', ''zero'', ''mirror'', ''gaussian'', or ''fixed''.');
                    end
                    
                    % Output the result
                    disp(['New size after padding: ', mat2str(size(outputArray))]);

                    %save the array as a tif
                    %I think this doesn't save metadata but that doesn't
                    %seem to matter for the deconvolution step
                    parallelWriteTiff(tifFullpath,outputArray);

                    %clear array for next channel
                    array = [];
                    count = 1;
                end

                %clear array for next timepoint
                array = [];
                count = 1;


            end
        end
        fprintf('Frame Interval: %.2f seconds\n', frameInterval);

        % After we have saved all the individual 3D stacks for each image
        % the current metadata will be correct and we can run deconv and
        % deskew as we go along then reconstruct into a new 5D image

        %% Step 2: Deconvolution 
        %% Step 2.1: set parameters 
        % set in top section
        
        %% Step 2.2: run the deconvolution with given parameters. 
        % the results will be saved in matlab_decon under the dataPaths. 
        % the next step is deskew/rotate (if in skewed space for x-stage scan) or 
        % rotate (if objective scan) or other processings. 
        fprintf('Starting deconvolution...\n\n');
        
       
        XR_decon_data_wrapper(tifDir, 'resultDirName', resultDirName, 'xyPixelSize', xyPixelSize, ...
            'dz', dz, 'Reverse', Reverse, 'ChannelPatterns', ChannelPatterns, 'PSFFullpaths', PSFFullpaths, ...
            'dzPSF', dzPSF, 'parseSettingFile', parseSettingFile, 'RLmethod', RLmethod, ...
            'wienerAlpha', wienerAlpha, 'OTFCumThresh', OTFCumThresh, 'skewed', skewed, ...
            'Background', Background, 'CPPdecon', false, 'CudaDecon', false, 'DeconIter', DeconIter, ...
            'fixIter', fixIter, 'EdgeErosion', EdgeErosion, 'Save16bit', Save16bit, ...
            'zarrFile', zarrFile, 'saveZarr', saveZarr, 'parseCluster', parseCluster, ...
            'largeFile', largeFile, 'GPUJob', GPUJob, 'debug', debug, 'cpusPerTask', cpusPerTask, ...
            'ConfigFile', ConfigFile, 'GPUConfigFile', GPUConfigFile, 'mccMode', mccMode);
        
        % release GPU if using GPU computing
        if GPUJob && gpuDeviceCount('available') > 0
            reset(gpuDevice);
        end
        
        %% Step 2.5 Crop the deconvolved output to remove the padding
        dataPath_exps = fullfile(tifDir, resultDirName);
        % Get list of .tif files in the folder
        fileList = dir(fullfile(dataPath_exps, '*.tif'));

        % Check if padding was applied (i.e., padding is not 'none')
        if ~strcmp(z_edge_padding, 'none')
            for k = 1:length(fileList)
                % Construct full file path
                filePath = fullfile(dataPath_exps, fileList(k).name);
                
                % Load the image
                img = parallelReadTiff(filePath);
                
                % Check if the image has the expected padding size
                if size(img, 3) > 2 * z_padding
                    % Remove the padding from the z-axis
                    img_no_padding = img(:, :, (z_padding + 1):(end - z_padding));
                    
                    parallelWriteTiff(filePath,img_no_padding);
                else
                    warning(['Skipping ', fileList(k).name, ': not enough depth for padding removal.']);
                end
            end
        end


        %% Step 3: deskew the deconvolved results
       
        XR_deskew_rotate_data_wrapper(dataPath_exps, skewAngle=skewAngle, flipZstack=flipZstack, DSRCombined=DSRCombined, rotate=rotate, xyPixelSize=xyPixelSize, dz=dz, ...
            Reverse=Reverse, ChannelPatterns=ChannelPatterns, largeFile=largeFile, ...
            zarrFile=zarrFile, saveZarr=saveZarr, Save16bit=Save16bit, parseCluster=parseCluster, ...
            masterCompute=masterCompute, configFile=configFile, mccMode=mccMode);
        
    end

end

% This was not clear, may need to be added just before the deconvolution
% step
% % move to the PetaKit5D root directory
% curPath = pwd;
% if ~endsWith(curPath, 'PetaKit5D')
%     mfilePath = mfilename('fullpath');
%     if contains(mfilePath,'LiveEditorEvaluationHelper')
%         mfilePath = matlab.desktop.editor.getActiveFilename;
%     end
% 
%     mPath = fileparts(mfilePath);
%     if endsWith(mPath, 'demos')
%         cd(mPath);
%         cd('..')
%     end
% end

%% Step 4: delete intermediate .tif files
 
% deletes the raw tifs if the flag is true
if deleteRawTif == true 

    % Find the raw .tif files (i.e. not deconvolved, not deskewed)
    filePattern = fullfile(tifDir, '*.tif'); 
    theFiles = dir(filePattern);
    
    % Store total number of .sld or .czi files to study
    nFiles = length(theFiles);
    
    % Iterate through all the .sld or .czi files in the directory
    for k = 1:nFiles        
    
        % Define full file name for current loop iteration
        baseFileName = theFiles(k).name;
        fullFileName = fullfile(theFiles(k).folder, baseFileName);
        delete(fullFileName);
    end
end

% deletes the .tif files that are deconvolved but not deskewed, if the flag is true
if deleteDeconTif == true 

    % Path to the deconvolved .tif files
    deconTifDir = fullfile(tifDir, resultDirName);
    % Find the raw .tif files (i.e. not deconvolved, not deskewed)
    
    filePattern = fullfile(deconTifDir, '*.tif'); 
    theFiles = dir(filePattern);
    
    % Store total number of .sld or .czi files to study
    nFiles = length(theFiles);
    
    % Iterate through all the .sld or .czi files in the directory
    for k = 1:nFiles
            
        % Define full file name for current loop iteration
        baseFileName = theFiles(k).name;
        fullFileName = fullfile(theFiles(k).folder, baseFileName);
        delete(fullFileName);
    end
end



