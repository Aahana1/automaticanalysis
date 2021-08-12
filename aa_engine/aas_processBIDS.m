function aap = aas_processBIDS(aap,varargin)
% Allow specify Subjects, Sessions and Events from Brain Imaging Data Structure (BIDS)
%
%       aap = aas_processBIDS(aap,[[<Name>,<Value>][,<Name>,<Value>]...])
%
% Required:
%     - aap.directory_conventions.rawdatadir: path to BIDS
%
% Relevant aap sub-fields:
%     - aap.acq_details.input.selected_subjects:
%           cell or char array of subjects to process
%     - aap.acq_details.input.selected_visits:
%           cell or char array of visits to process
%     - aap.acq_details.input.combinemultiple:
%           Combines multiple visits per subjects (default = false)
%     - aap.acq_details.input.selected_sessions:
%           selection of a subset of tasks/runs based on their names (e.g. 'task-001_run01')
%           - elements are strings: selecting for preprocessing and analysis
%           - elements are cells:
%               - one cell is a selection for one "aamod_firstlevel_model" (in the tasklist)
%               - tasks/runs selected for any "aamod_firstlevel_model" are pre-processed
%           (default = [], all tasks/runs are selected for both preprocessing and analysis)
%     - aap.acq_details.input.correctEVfordummies: whether number of
%           dummies should be take into account when defining onset times (default = true);
%           Also requires:
%               - aap.acq_details.numdummies: number of (acquired) dummy scans (default = 0);
%               - "repetition_time" (TR) specified in JSON header
%
%  Optional parameters (Name-Value pairs): specific for BIDS and add flexibility in the handling
%       of modelling (i.e., tsv) data. They can be combined as needed.
% 
%     - 'regcolumn':
%           column in events.tsv to use for firstlevel model (default = 'trial_type')           
%     - 'stripEventNames':
%           strip special characters from event names (default = false)
%     - 'omitNullEvents':
%           do not add "null" events to model (default = false)
%     - 'convertEventsToUppercase':
%           convert event names to uppercase as required for contrast specification based on
%           event names (default = false)
%     - 'maxEventNameLength:'
%           truncate event names longer than the specified value (default = inf)
%     - 'omitModeling':
%           return w/o processing modeling data (default = false)
% 
% CHANGE HISTORY:
%
%   M Jones WashU 2021 -- look for .nii if .nii.gz doesn't exist (structural and epi files only)
%   M Jones WashU 2020 -- added acq_details tsv processing options
%   J Carlin 2018 -- Update
%   Tibor Auer MRC CBU Cambridge 2015 -- new

global BIDSsettings;

% we need spm_select here...
SPMtool = aas_inittoolbox(aap,'spm');
SPMtool.load;

%% Init
BIDSsettings.directories.structDIR = 'anat';
BIDSsettings.directories.functionalDIR = 'func';
BIDSsettings.directories.fieldmapDIR = 'fmap';
BIDSsettings.directories.diffusionDIR = 'dwi';
BIDSsettings.combinemultiple = aap.acq_details.input.combinemultiple;
BIDSsettings.sessnames = aap.acq_details.input.selected_visits;
BIDSsettings.tasknames = aap.acq_details.input.selected_sessions;

argParse = inputParser;
argParse.addParameter('regcolumn','trial_type',@ischar);
argParse.addParameter('stripEventNames',false,@(x) islogical(x) || isnumeric(x));
argParse.addParameter('omitNullEvents',false,@(x) islogical(x) || isnumeric(x));
argParse.addParameter('convertEventsToUppercase',false,@(x) islogical(x) || isnumeric(x));
argParse.addParameter('maxEventNameLength',inf,@isnumeric);
argParse.addParameter('omitModeling',false,@(x) islogical(x) || isnumeric(x));
argParse.parse(varargin{:});

BIDSsettings.modelling = argParse.Results;

aap.directory_conventions.subjectoutputformat = '%s';
aap.directory_conventions.subject_directory_format = 3;

if ~aap.directory_conventions.continueanalysis
    sfx = 1;
    analysisid0 = aap.directory_conventions.analysisid;
    while exist(fullfile(aap.acq_details.root,aap.directory_conventions.analysisid),'dir')
        sfx = sfx + 1;
        aap.directory_conventions.analysisid = [analysisid0 '_' num2str(sfx)];
    end
end

if isfield(aap.tasksettings,'aamod_firstlevel_model')
    for m = 1:numel(aap.tasksettings.aamod_firstlevel_model)
        aap.tasksettings.aamod_firstlevel_model(m).xBF.UNITS  ='secs';
    end
end

%% Process
if BIDSsettings.combinemultiple
    aas_log(aap,false,'WARNING: You have selected combining multiple BIDS sessions!');
    aas_log(aap,false,'    Make sure that you have also set aap.options.autoidentify*_* appropriately!');
    aas_log(aap,false,'    N.B.: <aa sessionname> = <BIDS taskname>_<BIDS sessionname>');
end

% Set BIDS
BIDS = aap.directory_conventions.rawdatadir;

% Look for subjects
SUBJ = aap.acq_details.input.selected_subjects;
if isempty(SUBJ)    
    SUBJ = spm_select('List',aap.directory_conventions.rawdatadir,'dir','sub-.*');
end
SUBJ = intersect(SUBJ,spm_select('List',BIDS,'dir','sub-.*'));
if isempty(SUBJ)
    % avoid cryptic errors later
    aas_log(aap,true,sprintf('no subjects found in directory %s',...
        aap.directory_conventions.rawdatadir));
end

% 1st pass - Add sessions only
% 2ns pass - Add data
for p = [false true]
    for subj = reshape(SUBJ,1,[])
        subjID = subj{1};
        SESS = cellstr(spm_select('List',fullfile(BIDS,subjID),'dir','ses'));
        if ~isempty(BIDSsettings.sessnames)
            % check that custom sessnames exist for this subject
            SESS = intersect(SESS,BIDSsettings.sessnames);
            if numel(SESS) ~= numel(BIDSsettings.sessnames)
                aas_log(aap,false,sprintf('WARNING: did not find all specified sessnames for sub %s',subjID));
            end
        end
        if isempty(SESS)
            aap = add_data(aap,subjID,fullfile(BIDS,subjID),p);
        else
            for sess = reshape(SESS,1,[])
                aap = add_data(aap,fullfile(subjID,sess{1}),fullfile(BIDS,subjID,sess{1}),p);
            end
        end
    end
    if ~p && BIDSsettings.combinemultiple && (numel(SESS) > 1)
        % sort sessions
        sessstr = regexp(SESS,'-','split');
        sessstr = vertcat(sessstr{:});
        sessstr = sessstr(:,2);
        if numel(aap.acq_details.sessions) > 1
            sortind = sort_sessions(aap.acq_details.sessions,sessstr);
            aap.acq_details.sessions = aap.acq_details.sessions(sortind);
        end
        if numel(aap.acq_details.diffusion_sessions) > 1
            aap.acq_details.diffusion_sessions = aap.acq_details.diffusion_sessions(sort_sessions(aap.acq_details.diffusion_sessions,sessstr));
        end
    end
end

% take SPM off the path again (since the user might end up wanting a different SPM for
% actual data analysis)
SPMtool.unload;

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% UTILS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function aap = add_data(aap,mriname,sesspath,toAddData)

global BIDSsettings;
structDIR = BIDSsettings.directories.structDIR;
functionalDIR = BIDSsettings.directories.functionalDIR;
fieldmapDIR = BIDSsettings.directories.fieldmapDIR;
diffusionDIR = BIDSsettings.directories.diffusionDIR;

% locate first_level modules
stagenumModel(1) = struct('name','aamod_firstlevel_model','ind',...
    find(strcmp({aap.tasklist.main.module.name},'aamod_firstlevel_model')));
stagenumModel(2) = struct('name','aamod_firstlevel_model_1_config','ind',...
    find(strcmp({aap.tasklist.main.module.name},...
    'aamod_firstlevel_model_1_config')));

% Correct EV onstets for number of dummies?
numdummies = aap.acq_details.input.correctEVfordummies*aap.acq_details.numdummies;

% Combine multiple sessions into one
if BIDSsettings.combinemultiple
    subjname = strtok(mriname,'/');
else
    subjname = strrep(mriname,'/','_');
end
% subjname = strrep(subjname,'sub-','');

structuralimages = {};
functionalimages = {};
fieldmapimages = {};
diffusionimages = {};
specialimages = {};


for cf = cellstr(spm_select('List',sesspath,'dir'))'
    switch cf{1}
	case '.'
        case structDIR
            if ~toAddData, continue; end
            for sfx = {'T1w','T2w'}
                image = cellstr(spm_select('FPList',fullfile(sesspath,structDIR),[subjname '.*_' sfx{1} '.*.nii.gz']))';
                if isempty(image{1})
                image = cellstr(spm_select('FPList',fullfile(sesspath,structDIR),[subjname '.*_' sfx{1} '.*.nii$']))';
                end
                if isempty(image{1}), continue; end
                hdrfname = retrieve_file(fullfile(sesspath,structDIR,[subjname '_' sfx{1},'.json']));
                info = ''; if ~isempty(hdrfname{1}), info = loadjson_multi(hdrfname); end
                structuralimages = horzcat(structuralimages,struct('fname',image{1},'hdr',info));
            end
        case diffusionDIR
            for cfname = cellstr(spm_select('FPList',fullfile(sesspath,diffusionDIR),[subjname '.*_dwi.*.nii.gz']))
                sessfname = strrep_multi(basename(cfname{1}),{[subjname '_'] '.nii'},{'',''});
                [bvalfname, runstr] = retrieve_file(fullfile(sesspath,diffusionDIR,[subjname '_' sessfname '.bval'])); bvalfname = bvalfname{1}; % ASSUME only one instance
                bvecfname = retrieve_file(fullfile(sesspath,diffusionDIR,[subjname '_' sessfname '.bvec'])); bvecfname = bvecfname{1}; % ASSUME only one instance
                if ~isempty(bvalfname) && ~isempty(bvecfname)
                    sessname = strrep_multi(sessfname,{basename(sesspath) runstr},{'',''}); 
                    if sessname(1) == '_', sessname(1) = ''; end

                    if contains(basename(sesspath),'ses-')
                        sesstr = ['_' strrep(basename(sesspath),'ses-','')];
                    else
                        sesstr = '';
                    end
                    
                    if BIDSsettings.combinemultiple
                        sessname = [sessname,sesstr];
                    end
                    sessname = [sessname,runstr];
                    
                    aap = aas_add_diffusion_session(aap,sessname);
                    
                    if ~toAddData, continue; end
                    
                    aasessnames = {aap.acq_details.diffusion_sessions.name};
                    if BIDSsettings.combinemultiple && ~ isempty(sesstr)
                        aasessnames = aasessnames(cell_index(aasessnames,sesstr));
                    end
                    if isempty(diffusionimages), diffusionimages = cell(1,numel(aasessnames)); end
                    isess = strcmp(aasessnames,sessname);
                    diffusionimages{isess} = struct('fname',cfname{1},'bval',bvalfname,'bvec',bvecfname);
                else
                    aas_log(aap,true,sprintf('ERROR: No BVals/BVecs found for subject %s run %s!\n',subjname,sessfname))
                end
            end
        case fieldmapDIR
            if ~toAddData, continue; end
            
            fmaps = cellstr(spm_select('FPList',fullfile(sesspath,fieldmapDIR),[subjname '.*.json'])); % ASSUME next to the image
            skipnext = false;
            for f = fmaps'
                if skipnext
                    skipnext = false;
                    continue; 
                end
                jfname = spm_file(f{1},'basename');
                ind = find(jfname=='_',1,'last');
                ftype = jfname(ind+1:end);
                switch ftype
                    case 'phasediff'
                        fmap.hdr = {loadjson(f{1})};
                        if isfield(fmap.hdr{1},'IntendedFor')
                            fmap.session = cellstr(get_taskname(sesspath,subjname,fmap.hdr{1}.IntendedFor));
                        else
                            fmap.session = '*';
                        end
                        fmap.fname = cellstr(spm_select('FPList',fullfile(sesspath,fieldmapDIR),[strrep(jfname,ftype,'') '.*.nii.gz']));
                    case 'phase1'
                        skipnext = true;
                    case 'fieldmap'
                end
                fieldmapimages = horzcat(fieldmapimages,fmap);
            end            
        case functionalDIR
            allepi = cellstr(spm_select('FPList',...
                fullfile(sesspath,functionalDIR),[subjname '.*_task.*_bold.nii.gz']))';
            % if gz doesn't exist, see if unziped version does:
            if (isempty(allepi) || isempty(allepi{1}))
                allepi = cellstr(spm_select('FPList',fullfile(sesspath,functionalDIR),[subjname '.*_task.*_bold.nii$']))';
            end
            if ~isempty(BIDSsettings.tasknames)
                % identify target tasks, in correct order
                tasks = cellfun(@(x)get_taskname(sesspath,subjname,x),allepi,'uniformoutput',0);
                outepi = {};
                for t = BIDSsettings.tasknames(:)'
%                   thits = cell_index(tasks,t{1});
                    % cell_index(wawa,'foo') returns true for both 'foo...' and '...foo...'
                    % (so it can't differentiate between, say, "overt-foo" and "covert-foo")
                    % use startsWith() instead:
                    thits = find(startsWith(tasks,t{1}));
                    if all(thits)==0
                        aas_log(aap,true,'could not find task %s',t{1});
                    end
                    outepi = [outepi allepi(thits)];
                end
                allepi = outepi;
            end
            for cfname = allepi
                [~,n,~] = fileparts(strtok(cfname{1},'.'));
                taskfname = strrep_multi(n,{[subjname '_'] '_bold'},{'',''});
                [taskname, sesssfx] = get_taskname(sesspath,subjname,cfname{1});                              
                % Header
                info = []; TR = 0;
                hdrfname = retrieve_file(fullfile(sesspath,functionalDIR,[subjname '_' taskfname,'_bold.json']));
                if ~isempty(hdrfname{1})
                    info = loadjson_multi(hdrfname);
                    if isfield(info,'RepetitionTime'), TR = info.RepetitionTime; end
                end
                
                % Skip?
                if ~isempty(aap.acq_details.selected_sessions) && ~any(strcmp({aap.acq_details.sessions(aap.acq_details.selected_sessions).name},taskname)), continue; end
                aap = aas_addsession(aap,taskname);
                
                if ~toAddData, continue; end
                
                % Data
                aasessnames = {aap.acq_details.sessions.name};
                if BIDSsettings.combinemultiple && ~isempty(sesssfx)
                    aasessnames = aasessnames(cell_index(aasessnames,sesssfx));
                end
                if isempty(functionalimages), functionalimages = cell(1,numel(aasessnames)); end
                isess = strcmp(aasessnames,taskname);
                if isstruct(info)
                    functionalimages{isess} = struct('fname',cfname{1},'hdr',hdrfname);
                else
                    functionalimages{isess} = cfname{1};
                end
                
                % Model
                        
                if (BIDSsettings.modelling.omitModeling)                    
                    aas_log(aap,false,sprintf('INFO: Omitting addevent in aas_processBIDS'));
                else

                    for thisstage = stagenumModel
                        if any(thisstage.ind)
                            iModel = [];
                            for m = 1:numel(thisstage.ind)
                                sess = textscan(aap.tasklist.main.module(thisstage.ind(m)).extraparameters.aap.acq_details.selected_sessions,'%s'); sess = sess{1};
                                if any(strcmp(sess,'*')) || any(strcmp(sess,taskname)), iModel(end+1) = aap.tasklist.main.module(thisstage.ind(m)).index; end
                            end

                            if ~TR
                                aas_log(aap,false,sprintf('WARNING: No (RepetitionTime in) header found for subject %s task/run %s',subjname,taskname))
                                aas_log(aap,false,'WARNING: No correction of EV onset for dummies is possible!\n')
                            end

                            % Search for event file
                            eventfname = retrieve_file(fullfile(sesspath,functionalDIR,[subjname '_' taskfname '_events.tsv'])); eventfname = eventfname{1}; % ASSUME only one instance
                            if isempty(eventfname)
                                aas_log(aap,false,sprintf('WARNING: No event found for subject %s task/run %s\n',subjname,taskname));
                            else
                                EVENTS = tsvread(eventfname);
                                iName = cell_index(EVENTS(1,:),BIDSsettings.modelling.regcolumn);
                                iOns = cell_index(EVENTS(1,:),'onset');
                                iDur = cell_index(EVENTS(1,:),'duration');
                                if (BIDSsettings.modelling.stripEventNames)
                                    EVENTS(2:end,iName) = regexprep(EVENTS(2:end,iName),'[^a-zA-Z0-9]','');
                                end                         
                                names = unique(EVENTS(2:end,iName));
                                onsets = cell(numel(names),1);
                                durations = cell(numel(names),1);
                                for t = 2:size(EVENTS,1)
                                    iEV = strcmp(names,EVENTS{t,iName});
                                    onsets{iEV}(end+1) = str2double(EVENTS{t,iOns});
                                    durations{iEV}(end+1) = str2double(EVENTS{t,iDur});
                                end
                                if (BIDSsettings.modelling.convertEventsToUppercase)
                                    names = upper(names); 
                                end
                                if (BIDSsettings.modelling.maxEventNameLength < Inf)
                                    maxlen =  BIDSsettings.modelling.maxEventNameLength;
                                    names = cellfun(@(x) x(1:min(maxlen,length(x))), names,'UniformOutput',false);
                                end
                                for m = iModel
                                    for e = 1:numel(names)
                                        if (strcmpi(names{e},'null') && BIDSsettings.modelling.omitNullEvents)
                                            continue;
                                        end
                                        aap = aas_addevent(aap,sprintf('%s_%05d',thisstage.name,m),subjname,taskname,names{e},onsets{e}-numdummies*TR,durations{e});
                                    end
                                end
                            end
                        end
                    end
                end
            end
        otherwise
            aas_log(aap,false,sprintf('NYI: Input %s is not supported',cf{1}));
    end
end
if toAddData
    aap = aas_addsubject(aap,subjname,mriname,...
        'structural',structuralimages,...
        'functional',functionalimages,...
        'fieldmaps',fieldmapimages,...
        'diffusion',diffusionimages,...
        'specialseries',specialimages); 
end
end

function [outfname, runstr] = retrieve_file(fname)

% fully specified fname with fullpath
outfname = {''};

% pre-process fname
[p, f, e] = fileparts(fname);
tags = regexp(f,'_','split');
% suffix
if isempty(regexp(f(end),'[0-9]', 'once')) % last entry is suffix
    e = [tags{end} e];
    tags(end) = [];
end
ntags = 1:numel(tags);
f = list_index(f,1,ntags);
% suffix
itags = [cell_index(tags,'acq'), cell_index(tags,'run')]; itags(~itags) = [];
runstr = '';
for t = itags
    runstr = [runstr '_' tags{t}];
end

% search
itags = [cell_index(tags,'ses'), cell_index(tags,'sub')]; itags(~itags) = [];
itagrun = cell_index(tags,'run');

if exist(fname,'file'), outfname(end+1) = {fname}; end
if itagrun
    fname = fullfile(fullfile(p,[list_index(f,1,ntags(ntags~=itagrun),0) e])); % try without runnumber
    if exist(fname,'file'), outfname(end+1) = {fname}; end
end

p = fileparts(p);
for t = itags
    % one level up
    p = fileparts(p); ntags(t) = [];
    fname = fullfile(fullfile(p,[list_index(f,1,ntags,0) e]));
    if exist(fname,'file'), outfname(end+1) = {fname}; end
    if itagrun
        fname = fullfile(fullfile(p,[list_index(f,1,ntags(ntags~=itagrun),0) e])); % try without runnumber
        if exist(fname,'file'), outfname(end+1) = {fname}; end
    end
end
if exist(outfname{end},'file'), outfname(1) = []; end
end

function [taskname, sesstr] = get_taskname(sesspath,subjname,fname)
global BIDSsettings;
functionalDIR = BIDSsettings.directories.functionalDIR;
[~,n,~] = fileparts(strtok(fname,'.'));
taskfname = strrep_multi(n,{[subjname '_'] '_bold'},{'',''});
taskname = strrep(taskfname,'task-','');

% Header
[hdrfname, runstr] = retrieve_file(fullfile(sesspath,functionalDIR,[subjname '_' taskfname,'_bold.json']));
if ~isempty(hdrfname{1})
    info = loadjson_multi(hdrfname);
    if isfield(info,'TaskName')
        taskname = info.TaskName;
%         taskname = regexp(taskname,'[a-zA-Z0-9]*','match');
%         taskname = strcat(taskname{:});
        if contains(basename(sesspath),'ses-')
            sesstr = ['_' strrep(basename(sesspath),'ses-','')];
        else
            sesstr = '';
        end
        if BIDSsettings.combinemultiple            
            taskname = [taskname,sesstr];
        end
        taskname = [taskname,runstr];
    end
end
end

function sessord = sort_sessions(sessions,sessstr)
aasessnames = {sessions.name};
sessstr = spm_file(sessstr,'prefix','_');
sessord = [];
for sess = sessstr'
    sessord = horzcat(sessord, cell_index(aasessnames,sess{1})');
end
% filter out misses (e.g., anatomy-only sessions)
sessord(sessord==0) = [];
end

function info = loadjson_multi(fnamecell)
for f = numel(fnamecell):-1:1
   dat = loadjson(fnamecell{f}); 
   for field = fieldnames(dat)'
       info.(field{1}) = dat.(field{1});
   end
end
end

function LIST = tsvread(fname)
filestr = fileread(fname);
nLines = sum(double(filestr)==10);
LIST = textscan(filestr,'%s','Delimiter','\t');
LIST = reshape(LIST{1},[],nLines)';
end

function str = strrep_multi(str, old, new)
for i = 1:numel(old)
    str = strrep(str, old{i}, new{i});
end
end