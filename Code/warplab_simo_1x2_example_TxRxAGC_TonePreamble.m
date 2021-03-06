%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Transmitting and Receiving Data using WARPLab with Automatic Gain Control
% (SISO Configuration)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Before looking at this code we recommend getting familiar with the
% warplab_siso_example_TxRx.m code which doesn't use AGC hence it is easier
% to understand.

% The specific steps implemented in this script are the following

% 0. Initializaton and definition of parameters
% 1. Generate a vector of samples to transmit and send the samples to the 
% WARP board (Sample Frequency is 40MHz)
% 2. Prepare WARP boards for transmission and reception and send trigger to 
% start transmission and reception (trigger is the SYNC packet)
% 3. Read the received samples from the WARP board
% 4. Read values related to AGC
% 5. Reset and disable the boards
% 6. Plot the transmitted and received data and close sockets

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 0. Initializaton and definition of parameters
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%Load some global definitions (packet types, etc.)
warplab_defines

% Create Socket handles and intialize nodes
[socketHandles, packetNum] = warplab_initialize;

% Separate the socket handles for easier access
% The first socket handle is always the magic SYNC
% The rest of the handles are the handles to the WARP nodes
udp_Sync = socketHandles(1);
udp_node1 = socketHandles(2);
udp_node2 = socketHandles(3);

% Define WARPLab parameters. 
% For this experiment node 1 will be set as the transmitter and node 
% 2 will be set as the receiver (this is done later in the code), hence, 
% there is no need to define receive gains for node 1 and there is no
% need to define transmitter gains for node 2.
TxDelay = 0; % Number of noise samples per Rx capture. In [0:2^14]
TxLength = 2^14-1; % Length of transmission. In [0:2^14-1-TxDelay]
CarrierChannel = 12; % Channel in the 2.4 GHz band. In [1:14]
Node1_Radio2_TxGain_BB = 1; % Tx Baseband Gain. In [0:3]
Node1_Radio2_TxGain_RF = 25; % Tx RF Gain. In [0:63]
TxMode = 0; % Transmission mode. In [0:1] 
            % 0: Single Transmission 
            % 1: Continuous Transmission. Tx board will continue 
            % transmitting the vector of samples until the user manually
            % disables the transmitter. 
Node2_MGC_AGC_Select = 1;   % Set MGC_AGC_Select=1 to enable Automatic Gain Control (AGC). 
                            % Set MGC_AGC_Select=0 to enable Manual Gain Control (MGC).
                            % By default, the nodes are set to MGC.
Node2_TargetdBmAGC = -10; % AGC Target dBm. A larger target value will 
                          % result in larger Rx gains set by AGC. This is
                          % the value we tune if AGC is not setting gains
                          % correctly.
Node2_NoiseEstdBmAGC = -95; % Noise power in dBm. -95dBm is a reasonable 
            % value for wireless. If AGC is not setting gains correctly
            % this value may need to be modified. Usually we first try to
            % change the TargetdBmAGC  before changing the NoiseEstdBmAGC 
Node2_Thresh1 = -90; 
Node2_Thresh2 = -53;
Node2_Thresh3 = -43;
% Change format of Thresholds so they can be correctly understood by
% the FPGA:
Node_2Thresholds = uint32(Node2_Thresh3+2^8)*2^16+uint32(Node2_Thresh2+2^8)*2^8+uint32(Node2_Thresh1+2^8);
% The three thresholds above are used to set the Rx RF gain. If the RSSI in
% dBm of the received signal is less than -90 then the AGC declares the
% signal to be too low and quits. If the RSSI in dBm of the received signal
% is between -53 and -90 then the AGC selects the largest RF gain : 3. If 
% the RSSI dBm is between -43 and -53 then the AGC sets medium RF gain : 2. If
% the RSSI dBm is larger than -43 then the AGC sets low RF gain :1.
% If AGC is no setting gains correctly then these three thresholds may need
% to be modified. Usually we first try to change the TargetdBmAGC  before
% changing the Thresholds.
% Remember there are 3 possible Rx RF gains: 1,2,3. Each step corresponds
% to 15dB: Changing the gain from 2 to 3 increases the Rx gain by 15 dB.
Node2_AGCTrigger_nsamps_delay = 100; % The AGC core should not be started before the 
% signal arrives. If TxDelay=0 then Tx and Rx should start at exactly the
% same time (upon reception of magic sync) however, because of jitter in
% reception of the magic sync, it may happed that the Rx gets the magic
% sync before the Tx. If this is the case then the AGC will set wrong gains
% because AGC will use RSSI values that are measured before reception of the signal.
% To avoid this we can delay the trigger of the AGC core by 
% Node2_AGCTrigger_nsamps_delay samples relative to the reception of the
% magic sync. We recommend to set this value between 0 and 50 samples. We
% have not observed magic sync jitters greater than 50 samples.
Node2_Enable_DCOffset_Correction = 1; % Enable/disable correction of DC Offsets (DCO). 
% Node2_Enable_DCOffset_Correction = 0; Disable correction of DC Offsets at
% AGC
% Node2_Enable_DCOffset_Correction = 1; Enable correction of DC Offsets at
% AGC
% Change of Rx gains by AGC may result in DC offsets. The AGC can correct
% these offsets but the user must be very careful on the choice of preamble
% used for AGC. For DCO correction at AGC to work properly the first 320
% samples must correspond to a periodic signal with an average (DC) of zero
% over 32 consecutive samples, this will generate the right signal required
% by AGC DCO correction for a sampling frequency of 40 MHz. AGC DCO
% correction can be disabled by setting Node2_Enable_DCOffset_Correction=0,
% in this case there is no requirement for the periodicity of the
% preamble used for AGC.

% NOTES ON AGC: 
% 1.    As soon as AGC is triggered, it takes the AGC core
% approximately 250 samples (at 40MHz sampling frequency) to set gains. If
% DCO correction at AGC is enabled it takes the AGC an extra 32 samples to
% filter DCO. This means that the first 250 samples received (282 when using DCO
% correction) may not contain useful data because during reception of these
% samples Rx gains (and DCO correction) were not set correctly. 
% 2.     The first 250 samples must be representative of the rest of signal
% being transmitted (similar bandwidth and amplitude), otherwise the gains 
% set by the AGC will work for the first 250 samples but will be wrong 
% (causing saturation or underflow) for the rest of the signal.

% Download the WARPLab parameters to the WARP nodes. 
% The nodes store the TxDelay, TxLength, and TxMode parameters in 
% registers defined in the WARPLab sysgen model. The nodes set radio 
% related parameters CarrierChannel, TxGains, and RxGains, using the 
% radio controller functions.

% The TxDelay, TxLength, and TxMode parameters need to be known at the transmitter;
% the receiver doesn't require knowledge of these parameters (the receiver
% will always capture 2^14 samples). For this exercise node 1 will be set as
% the transmitter (this is done later in the code). Since TxDelay, TxLength and
% TxMode are only required at the transmitter we download the TxDelay, TxLength and
% TxMode parameters only to the transmitter node (node 1).
warplab_writeRegister(udp_node1,TX_DELAY,TxDelay);
warplab_writeRegister(udp_node1,TX_LENGTH,TxLength);
warplab_writeRegister(udp_node1,TX_MODE,TxMode);
% The CarrierChannel parameter must be downloaded to all nodes  
warplab_setRadioParameter(udp_node1,CARRIER_CHANNEL,CarrierChannel);
warplab_setRadioParameter(udp_node2,CARRIER_CHANNEL,CarrierChannel);
% Node 1 will be set as the transmitter so download Tx gains to node 1.
warplab_setRadioParameter(udp_node1,RADIO2_TXGAINS,(Node1_Radio2_TxGain_RF + Node1_Radio2_TxGain_BB*2^16));
% Node 2 will be set as the receiver so download AGC related parameters to node 2.
warplab_setAGCParameter(udp_node2,MGC_AGC_SEL, Node2_MGC_AGC_Select); % AGC mode is enabled when 
% Node2_MGC_AGC_Select = 1. THIS COMMAND RESETS AND INITIALIZES THE AGC. THIS COMMAND INITIALIZES 
% AGC PARAMETER TO DEFAULTS. Default values are hard coded in warplab C code. 
% The default values can be changed as is done in the 5 lines below.
warplab_setAGCParameter(udp_node2,SET_AGC_TARGET_dBm, Node2_TargetdBmAGC);
warplab_setAGCParameter(udp_node2,SET_AGC_NOISEEST_dBm, Node2_NoiseEstdBmAGC);
warplab_setAGCParameter(udp_node2,SET_AGC_THRESHOLDS, Node_2Thresholds);
warplab_setAGCParameter(udp_node2,SET_AGC_TRIG_DELAY, Node2_AGCTrigger_nsamps_delay);
warplab_setAGCParameter(udp_node2,SET_AGC_DCO_EN_DIS, Node2_Enable_DCOffset_Correction);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 1. Generate a vector of samples to transmit and send the samples to the 
% WARP board (Sample Frequency is 40MHz)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t = 0:(1/40e6):TxLength/40e6 - 1/40e6; % Create time vector.

% Create a signal to transmit, the signal is a function of the time vector 
% 't' the signal can be real or complex. 

% The signal must meet the following requirements:
% - Signal to transmit must be a row vector.
% - The amplitude of the real part must be in [-1:1] and the amplitude 
% of the imaginary part must be in [-1:1]. 
% - Highest frequency component is limited to 9.5 MHz (signal bandwidth
% is limited to 19 MHz)
% - Lowest frequency component is limited to 30 kHz

Node1_Radio2_TxData = exp(t*j*2*pi*2.5e6); % Generate 2.5 MHz signal. 
% Notice that with a sampling frequency of 40 MHz this signal is periodic
% every 32 samples and has an average DC of zero. Hence, DC Offset
% correction will work for this signal.

% Download the samples to be transmitted
warplab_writeSMWO(udp_node1, RADIO2_TXDATA, Node1_Radio2_TxData);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 2. Prepare WARP boards for transmission and reception and send trigger to 
% start transmission and reception (trigger is the SYNC packet)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% The following lines of code set node 1 as transmitter and node 2 as
% receiver; transmission and capture are triggered by sending the SYNC
% packet.

% Enable transmitter radio path in radio 2 in node 1 (enable radio 2 in 
% node 1 as transmitter)
warplab_sendCmd(udp_node1, RADIO2_TXEN, packetNum);

% Enable transmission of node1's radio 2 Tx buffer (enable transmission
% of samples stored in radio 2 Tx Buffer in node 1)
warplab_sendCmd(udp_node1, RADIO2TXBUFF_TXEN, packetNum);

% Enable receiver radio path in radios 2 and 3 in node 2 (enable radio 2 
% and radio 3 in node 2 as receiver)
warplab_sendCmd(udp_node2, [RADIO2_RXEN RADIO3_RXEN], packetNum);

% Enable capture in node2's radio 2 and radio 3 Rx Buffer (enable radio 2 rx buffer 
% and radio 3 rx buffer in node 2 for storage of samples)
warplab_sendCmd(udp_node2, [RADIO2RXBUFF_RXEN RADIO3RXBUFF_RXEN], packetNum);

% Prime transmitter state machine in node 1. Node 1 will be 
% waiting for the SYNC packet. Transmission from node 1 will be triggered 
% when node 1 receives the SYNC packet.
warplab_sendCmd(udp_node1, TX_START, packetNum);

% Prime receiver state machine in node 2. Node 2 will be waiting 
% for the SYNC packet. Capture at node 2 will be triggered when node 2 
% receives the SYNC packet.
warplab_sendCmd(udp_node2, RX_START, packetNum);

% Send the SYNC packet
warplab_sendSync(udp_Sync);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 3. Read the received samples from the WARP board
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Read back the received samples
[Node2_Radio2_RawRxData] = warplab_readSMRO(udp_node2, RADIO2_RXDATA, TxLength+TxDelay);
[Node2_Radio3_RawRxData] = warplab_readSMRO(udp_node2, RADIO3_RXDATA, TxLength+TxDelay);
% Process the received samples to obtain meaningful data
[Node2_Radio2_RxData,Node2_Radio2_RxOTR] = warplab_processRawRxData(Node2_Radio2_RawRxData);
[Node2_Radio3_RxData,Node2_Radio3_RxOTR] = warplab_processRawRxData(Node2_Radio3_RawRxData);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 4. Read values related to AGC
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Read the sample number that corresponds to AGC being done setting gains
[Node2_AGC_Set_Addr] = warplab_readAGCValue(udp_node2, READ_AGC_DONE_ADDR);
% Received samples are stored in Received buffer, when AGC is done the
% address of the sample being written at that moment is stored, this
% address is Node2_AGC_Set_Addr. This means that samples after
% Node2_AGC_Set_Addr sample are applied the Rx Gains computed by AGC. From
% sample zero the Node2_AGC_Set_Addr the amplitude of the received signal
% may vary a lot because during this time the AGC was not done setting
% gains.

% Read the value of the RSSI that corresponds to AGC being done setting
% gains. When AGC is done the currrent RSSI value measured by node 2 radio2
% and radio 3 is stored in registers which can be read as shown below.
[Node2_Radio2_AGC_Set_RSSI] = warplab_readAGCValue(udp_node2, READ_RADIO2AGCDONERSSI);
[Node2_Radio3_AGC_Set_RSSI] = warplab_readAGCValue(udp_node2, READ_RADIO3AGCDONERSSI);

% Read the gains set by AGC
[Node2_Raw_AGC_Set_Gains] = warplab_readAGCValue(udp_node2, READ_AGC_GAINS);
[Node2_GainsRF,Node2_GainsBB] = warplab_processRawAGCGainsData(Node2_Raw_AGC_Set_Gains);
% Since only radio 2 and 3 were used then we only care about the second and third entries in 
% Node2_GainsRF and Node2_GainsBB vectors
Node2_Radio2_GainsRF = Node2_GainsRF(2);
Node2_Radio2_GainsBB = Node2_GainsBB(2);
Node2_Radio3_GainsRF = Node2_GainsRF(3);
Node2_Radio3_GainsBB = Node2_GainsBB(3);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 5. Reset and disable the boards
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Set radio 2 Tx buffer in node 1 back to Tx disabled mode
warplab_sendCmd(udp_node1, RADIO2TXBUFF_TXDIS, packetNum);

% Disable the transmitter radio
warplab_sendCmd(udp_node1, RADIO2_TXDIS, packetNum);

% Set radio 2 and 3 Rx buffer in node 2 back to Rx disabled mode
warplab_sendCmd(udp_node2, [RADIO2RXBUFF_RXDIS RADIO3RXBUFF_RXDIS], packetNum);

% Disable the receiver radios
warplab_sendCmd(udp_node2, [RADIO2_RXDIS RADIO3_RXDIS], packetNum);

% Resets Rx gains to default values of RF Gain of 3 and Baseband gain of
% 26. Sets AGC ready for a new capture.
warplab_sendCmd(udp_node2, AGC_RESET, packetNum);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 6. Plot the transmitted and received data and close sockets
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
figure;
subplot(3,2,1);
plot(real(Node1_Radio2_TxData));
title('Tx Node 1 Radio 2 I');
xlabel('n (samples)'); ylabel('Amplitude');
axis([0 2^14 -1 1]); % Set axis ranges.
subplot(3,2,2);
plot(imag(Node1_Radio2_TxData));
title('Tx Node 1 Radio 2 Q');
xlabel('n (samples)'); ylabel('Amplitude');
axis([0 2^14 -1 1]); % Set axis ranges.
subplot(3,2,3);
plot(real(Node2_Radio2_RxData));
title('Rx Node 2 Radio 2 I');
xlabel('n (samples)'); ylabel('Amplitude');
axis([0 2^14 -1 1]); % Set axis ranges.
subplot(3,2,4);
plot(imag(Node2_Radio2_RxData));
title('Rx Node 2 Radio 2 Q');
xlabel('n (samples)'); ylabel('Amplitude');
axis([0 2^14 -1 1]); % Set axis ranges.
subplot(3,2,5);
plot(real(Node2_Radio3_RxData));
title('Rx Node 2 Radio 3 I');
xlabel('n (samples)'); ylabel('Amplitude');
axis([0 2^14 -1 1]); % Set axis ranges.
subplot(3,2,6);
plot(imag(Node2_Radio3_RxData));
title('Rx Node 2 Radio 3 Q');
xlabel('n (samples)'); ylabel('Amplitude');
axis([0 2^14 -1 1]); % Set axis ranges.

% Close sockets
pnet('closeall');