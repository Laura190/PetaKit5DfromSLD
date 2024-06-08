function [] = demo_light_sheet_cell_data_downloader(destPath)
% automatically download demo dataset from Dropbox


if nargin == 0 || isempty(destPath)
    warning('The destination path does not exist, save dataset to ~/Downloads/!')
    if ispc
        destPath = fullfile(getenv('USERPROFILE'), 'Downloads');   
    else
        destPath = '~/Downloads/';
    end
end

if ispc
    destPath = strrep(destPath, '\', '/');
end

dataPath = [strip(destPath, 'right', '/'), '/PetaKit5D_demo_cell_image_dataset/'];

% check if dataset already downloaded
if exist(dataPath, 'dir')
    % check if all necessary files exist
    dir_info = dir([dataPath, '/*']);
    fsns = {dir_info.name};
    
    file_exist = true;
    
    % tile files
    file_exist = file_exist && sum(matches(fsns, "Scan" + wildcardPattern + "tif")) == 16;

    % image list
    file_exist = file_exist && sum(matches(fsns, "ImageList_from_encoder.csv")) == 1;
    
    % PSF
    file_exist = file_exist && sum(matches(fsns, "PSF")) == 1;
    
    % Flat field
    file_exist = file_exist && sum(matches(fsns, "FF")) == 1;
    
    % check if PSF and FF files exist
    if file_exist
        dir_info = dir([dataPath, 'PSF/*tif']);
        fsns = {dir_info.name};
        file_exist = file_exist && numel(fsns) == 2;

        % check RW PSFs
        if exist([dataPath, 'PSF/RW_PSFs'], 'dir')
            dir_info = dir([dataPath, 'PSF/RW_PSFs/*tif']);
            fsns = {dir_info.name};
            file_exist = file_exist && numel(fsns) == 2;
        else
            file_exist = false;
        end

        dir_info = dir([dataPath, 'FF/averaged/*tif']);
        fsns = {dir_info.name};
        file_exist = file_exist && numel(fsns) == 2;

        dir_info = dir([dataPath, 'FF/KorraFusions/*tif']);
        fsns = {dir_info.name};
        file_exist = file_exist && numel(fsns) == 2;
    end
    
    if file_exist
        fprintf('The dataset already exists in "%s", skip downloading!\n', dataPath);
        return;
    end
end

% The demo dataset is available in zenodo (https://zenodo.org/records/11492027). We also shared the dataset from
% Drobox to allow much faster downloads. 
% url = 'https://zenodo.org/records/11492027/files/PetaKit5D_demo_cell_image_dataset.tar?download=1';
url = 'https://www.dropbox.com/scl/fi/1xr8jjvta45hqo1ejp2s6/PetaKit5D_demo_cell_image_dataset.tar?rlkey=0glipffj32l212ul7aw4rjl1y&st=1smi4rlv&dl=1';

fprintf('Download demo dataset from Dropbox...\n')
filename = [destPath, '/PetaKit5D_demo_cell_image_dataset.tar'];
outputfilename = websave(filename, url);

fprintf('Download finished! \nUntar dataset...\n')
if ~ismac
    untar(outputfilename, destPath);
else
    system(sprintf('tar -vxf %s/PetaKit5D_demo_cell_image_dataset.tar -C %s', destPath, destPath));
end

fprintf('Untar dataset finished! \nDelete the tar file...\n');
delete(outputfilename);

fprintf('Done!\n');

end
