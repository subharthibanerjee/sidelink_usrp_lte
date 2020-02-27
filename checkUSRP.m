function [] =checkUSRP()
    % Check that LTE Toolbox is installed, and that there is a valid license
    if isempty(ver('lte')) % Check for LST install
        error('usrpe3xxLTEMIMOTransmitReceive:NoLST', ...
            'Please install LTE Toolbox to run this example.');
    elseif ~license('test', 'LTE_Toolbox') % Check that a valid license is present
        error('usrpe3xxLTEMIMOTransmitReceive:NoLST', ...
            'A valid license for LTE Toolbox is required to run this example.');
    end
    
    % Setup handle for image plot
    if ~exist('imFig', 'var') || ~ishandle(imFig)
        imFig = figure;
        imFig.NumberTitle = 'off';
        imFig.Name = 'Image Plot';
        imFig.Visible = 'off';
    else
        clf(imFig); % Clear figure
        imFig.Visible = 'off';
    end

    % Setup handle for channel estimate plots
    if ~exist('hhest', 'var') || ~ishandle(hhest)
        hhest = figure('Visible','Off');
        hhest.NumberTitle = 'off';
        hhest.Name = 'Channel Estimate';
    else
        clf(hhest); % Clear figure
        hhest.Visible = 'off';
    end

    % Setup Spectrum viewer
    spectrumScope = dsp.SpectrumAnalyzer( ...
        'SpectrumType',    'Power density', ...
        'SpectralAverages', 10, ...
        'YLimits',         [-130 -40], ...
        'Title',           'Received Baseband LTE Signal Spectrum', ...
        'YLabel',          'Power spectral density');

    % Setup the constellation diagram viewer for equalized PDSCH symbols
    constellation = comm.ConstellationDiagram('Title','Equalized PDSCH Symbols',...
                                    'ShowReferenceConstellation',false);
                                
    %  Initialize SDR device
    txsim = struct; % Create empty structure for transmitter
    txsim.SDRDeviceName = 'B210'; % Set SDR Device
    radioFound = false;
    radiolist = findsdru;
    for i = 1:length(radiolist)
      if strcmp(radiolist(i).Status, 'Success')
        if strcmp(radiolist(i).Platform, 'B210')
            radio = comm.SDRuReceiver('Platform','B210', ...
                     'SerialNum', radiolist(i).SerialNum);
            radio.MasterClockRate = 1.92e6 * 4; % Need to exceed 5 MHz minimum
            radio.DecimationFactor = 4;         % Sampling rate is 1.92e6
            radioFound = true;
            break;
        end
        if (strcmp(radiolist(i).Platform, 'X300') || ...
            strcmp(radiolist(i).Platform, 'X310'))
            radio = comm.SDRuReceiver('Platform',radiolist(i).Platform, ...
                     'IPAddress', radiolist(i).IPAddress);
            radio.MasterClockRate = 184.32e6;
            radio.DecimationFactor = 96;        % Sampling rate is 1.92e6
            radioFound = true;
        end
      end
    end

    if ~radioFound
        error(message('sdru:examples:NeedMIMORadio'));
    end      
    
    txsim.RC = 'R.7';       % Base RMC configuration, 10 MHz bandwidth
    txsim.NCellID = 88;     % Cell identity
    txsim.NFrame = 700;     % Initial frame number
    txsim.TotFrames = 1;    % Number of frames to generate
    txsim.DesiredCenterFrequency = 2.45e9; % Center frequency in Hz
    txsim.NTxAnts = 2;      % Number of transmit antennas
    
    % TX gain parameter:
    % Change this parameter to reduce transmission quality, and impair the
    % signal. Suggested values:
    %    * set to -10 for default gain (-10dB)
    %    * set to -20 for reduced gain (-20dB)
    %
    % NOTE: These are suggested values -- depending on your antenna
    % configuration, you may have to tweak these values.
    txsim.Gain = -10;
    
    
    % Input an image file and convert to binary stream
    fileTx = 'peppers.png';            % Image file name
    fData = imread(fileTx);            % Read image data from file
    scale = 0.5;                       % Image scaling factor
    origSize = size(fData);            % Original input image size
    scaledSize = max(floor(scale.*origSize(1:2)),1); % Calculate new image size
    heightIx = min(round(((1:scaledSize(1))-0.5)./scale+0.5),origSize(1));
    widthIx = min(round(((1:scaledSize(2))-0.5)./scale+0.5),origSize(2));
    fData = fData(heightIx,widthIx,:); % Resize image
    imsize = size(fData);              % Store new image size
    binData = dec2bin(fData(:),8);     % Convert to 8 bit unsigned binary
    trData = reshape((binData-'0').',1,[]).'; % Create binary stream

    
    
    % Plot transmit image
    figure(imFig);
    imFig.Visible = 'on';
    subplot(211);
        imshow(fData);
        title('Transmitted Image');
    subplot(212);
        title('Received image will appear here...');
        set(gca,'Visible','off'); % Hide axes
        set(findall(gca, 'type', 'text'), 'visible', 'on'); % Unhide title

    pause(1); % Pause to plot Tx image
    
    
    %% transmitter ----
    % Create RMC
    rmc = lteRMCDL(txsim.RC);

    % Calculate the required number of LTE frames based on the size of the
    % image data
    trBlkSize = rmc.PDSCH.TrBlkSizes;
    txsim.TotFrames = ceil(numel(trData)/sum(trBlkSize(:)));

    % Customize RMC parameters
    rmc.NCellID = txsim.NCellID;
    rmc.NFrame = txsim.NFrame;
    rmc.TotSubframes = txsim.TotFrames*10; % 10 subframes per frame
    rmc.CellRefP = txsim.NTxAnts; % Configure number of cell reference ports
    rmc.PDSCH.RVSeq = 0;

    % Fill subframe 5 with dummy data
    rmc.OCNGPDSCHEnable = 'On';
    rmc.OCNGPDCCHEnable = 'On';

    % If transmitting over two channels enable transmit diversity
    if rmc.CellRefP == 2
        rmc.PDSCH.TxScheme = 'TxDiversity';
        rmc.PDSCH.NLayers = 2;
        rmc.OCNGPDSCH.TxScheme = 'TxDiversity';
    end

    fprintf('\nGenerating LTE transmit waveform:\n')
    fprintf('  Packing image data into %d frame(s).\n\n', txsim.TotFrames);

    % Pack the image data into a single LTE frame
    [eNodeBOutput,txGrid,rmc] = lteRMCDLTool(rmc,trData);
    
    sdrTransmitter = sdrtx(txsim.SDRDeviceName);
    sdrTransmitter.BasebandSampleRate = rmc.SamplingRate; % 15.36 Msps for default RMC (R.7)
                                              % with a bandwidth of 10 MHz
    sdrTransmitter.CenterFrequency = txsim.DesiredCenterFrequency;
    sdrTransmitter.ShowAdvancedProperties = true;
    sdrTransmitter.BypassUserLogic = true;
    sdrTransmitter.Gain = txsim.Gain;

    % Apply TX channel mapping
    if txsim.NTxAnts == 2
        fprintf('Setting channel map to ''[1 2]''.\n\n');
        sdrTransmitter.ChannelMapping = [1,2];
    else
        fprintf('Setting channel map to ''1''.\n\n');
        sdrTransmitter.ChannelMapping = 1;
    end

    % Scale the signal for better power output.
    powerScaleFactor = 0.8;
    if txsim.NTxAnts == 2
        eNodeBOutput = [eNodeBOutput(:,1).*(1/max(abs(eNodeBOutput(:,1)))*powerScaleFactor) ...
                        eNodeBOutput(:,2).*(1/max(abs(eNodeBOutput(:,2)))*powerScaleFactor)];
    else
        eNodeBOutput = eNodeBOutput.*(1/max(abs(eNodeBOutput))*powerScaleFactor);
    end

    % Cast the transmit signal to int16 ---
    % this is the native format for the SDR hardware.
    eNodeBOutput = int16(eNodeBOutput*2^15);
    
    sdrTransmitter.transmitRepeat(eNodeBOutput);
    
    
    
    
    
    %% receiver
    
    % User defined parameters --- configure the same as transmitter
    rxsim = struct;
    rxsim.RadioFrontEndSampleRate = sdrTransmitter.BasebandSampleRate; % Configure for same sample rate
                                                           % as transmitter
    rxsim.RadioCenterFrequency = txsim.DesiredCenterFrequency;
    rxsim.NRxAnts = txsim.NTxAnts;
    rxsim.FramesPerCapture = txsim.TotFrames+1; % Number of LTE frames to capture.
                                              % Capture 1 more LTE frame than transmitted to
                                              % allow for timing offset wraparound...
    rxsim.numCaptures = 1; % Number of captures

    % Derived parameters
    samplesPerFrame = 10e-3*rxsim.RadioFrontEndSampleRate; % LTE frames period is 10 ms

    captureTime = rxsim.FramesPerCapture * 10e-3; % LTE frames period is 10 m
    
    rxsim.SDRDeviceName = txsim.SDRDeviceName;

    sdrReceiver = sdrrx(rxsim.SDRDeviceName);
    sdrReceiver.BasebandSampleRate = rxsim.RadioFrontEndSampleRate;
    sdrReceiver.CenterFrequency = rxsim.RadioCenterFrequency;
    sdrReceiver.OutputDataType = 'double';

    % Configure RX channel map
    if rxsim.NRxAnts == 2
        sdrReceiver.ChannelMapping = [1,2];
    else
        sdrReceiver.ChannelMapping = 1;
    end
    
end