%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Transmitting and Receiving Data using WARPLab (SISO Configuration) and
% example on how to set Tx and Rx Low Pass Filter (LPF) Bandwidths
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% To run this M-code the boards must be programmed with the
% 2x2 MIMO 5.x version of WARPLab bitstream (because this bitstream provides 
% storage of RSSI values and this M-code reads RSSI values). This M-code 
% will work with the warplab_mimo_4x4_v05.bit bitstream when reading of
% RSSI values is deleted from the M-code.

% The specific steps implemented in this script are the following

% 0. Initializaton and definition of parameters (Including change of Tx and Rx
% Low Pass Filter Bandwidths)
% 1. Generate a chirp (sweeping sinusoid) to transmit and send the samples to the 
% WARP board (Sample Frequency is 40MHz)
% 2. Prepare WARP boards for transmission and reception and send trigger to 
% start transmission and reception (trigger is the SYNC packet)
% 3. Read the received samples from the WARP board
% 4. Reset and disable the boards
% 5. Plot the transmitted and received data and close sockets

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
TxLength = 2^14-2; % Length of transmission. In [0:2^14-1-TxDelay]
CarrierChannel = 8; % Channel in the 2.4 GHz band. In [1:14]
Node1_Radio2_TxGain_BB = 3; % Tx Baseband Gain. In [0:3]
Node1_Radio2_TxGain_RF = 60; % Tx RF Gain. In [0:63]
Node2_Radio2_RxGain_BB = 14; % Rx Baseband Gain. In [0:31]
Node2_Radio2_RxGain_RF = 1; % Rx RF Gain. In [1:3]  
TxMode = 0; % Transmission mode. In [0:1] 
            % 0: Single Transmission 
            % 1: Continuous Transmission. Tx board will continue 
            % transmitting the vector of samples until the user manually
            % disables the transmitter. 
Node2_MGC_AGC_Select = 0;   % Set MGC_AGC_Select=1 to enable Automatic Gain Control (AGC). 
                            % Set MGC_AGC_Select=0 to enable Manual Gain Control (MGC).
                            % By default, the nodes are set to MGC.  
Node1_Tx_LowPassFilt = 1; % Transmitter Low Pass Filter (LPF) bandwidth. In [1:3]
                   % 1: 12 MHz (nominal mode)
                   % 2: 18 MHz (turbo mode 1)
                   % 3: 24 MHz (turbo mode 2)
Node2_Rx_LowPassFilt = 3; % Receiver Low Pass Filter (LPF) bandwidth. In [0:3]
                   % 0: 7.5 MHz 
                   % 1: 9.5 MHz (nominal mode)
                   % 2: 14 MHz (turbo mode 1)
                   % 3: 18 MHz (turbo mode 2)                   

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
% Node 2 will be set as the receiver so download Rx gains to node 2.
warplab_setRadioParameter(udp_node2,RADIO2_RXGAINS,(Node2_Radio2_RxGain_BB + Node2_Radio2_RxGain_RF*2^16));
% Node 1 will be set as the transmitter so download desired TX LPF setting.
warplab_setRadioParameter(udp_node1,TX_LPF_CORN_FREQ,Node1_Tx_LowPassFilt);
% Node 2 will be set as the receiver so download desired TX LPF setting.
warplab_setRadioParameter(udp_node2,RX_LPF_CORN_FREQ,Node2_Rx_LowPassFilt); 
% Set MGC mode in node 2 (receiver)
warplab_setAGCParameter(udp_node2,MGC_AGC_SEL, Node2_MGC_AGC_Select);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 1. Generate a vector of samples to transmit and send the samples to the 
% WARP board (Sample Frequency is 40MHz)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Prepare some data to be transmitted
TxLength = 2^14;
t = 0:(1/40e6):TxLength/40e6 - 1/40e6; % Create time vector.

% Create frequency vector for sweep
fmin = 0;
fmax = 20e6;
% Second derivative of phase is slope of linear increase of frequency with
% time 
d2phase_dt = (fmax-fmin)/t(end); 
% Integrate twice to get phase as a function of time
phase_t = (1/2)*d2phase_dt*t.^2 + fmin *t; 

Node1_Radio2_TxData = exp(j*2*pi*phase_t); % chirp starts at DC and ends at 18MHz                                              

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

% Enable receiver radio path in radio 2 in node 2 (enable radio 2 in
% node 2 as receiver)
warplab_sendCmd(udp_node2, RADIO2_RXEN, packetNum);

% Enable capture in node2's radio 2 Rx Buffer (enable radio 2 rx buffer in
% node 2 for storage of samples)
warplab_sendCmd(udp_node2, RADIO2RXBUFF_RXEN, packetNum);

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
% Process the received samples to obtain meaningful data
[Node2_Radio2_RxData,Node2_Radio2_RxOTR] = warplab_processRawRxData(Node2_Radio2_RawRxData);
% Read stored RSSI data
[Node2_Radio2_RawRSSIData] = warplab_readSMRO(udp_node2, RADIO2_RSSIDATA, ceil((TxLength+TxDelay)/8));
% Procecss Raw RSSI data to obtain meningful RSSI values
[Node2_Radio2_RSSIData] = warplab_processRawRSSIData(Node2_Radio2_RawRSSIData);
% Note: If the two lines of code above (warplab_processRawRSSIData line and
% warplab_readSMRO(udp_node2, RADIO2_RSSIDATA, (TxLength+TxDelay)/8) line)
% are deleted, then the code will work when the boards are programmed
% with the warplab_mimo_4x4_v04.bit bitstream)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 4. Reset and disable the boards
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Set radio 2 Tx buffer in node 1 back to Tx disabled mode
warplab_sendCmd(udp_node1, RADIO2TXBUFF_TXDIS, packetNum);

% Disable the transmitter radio
warplab_sendCmd(udp_node1, RADIO2_TXDIS, packetNum);

% Set radio 2 Rx buffer in node 2 back to Rx disabled mode
warplab_sendCmd(udp_node2, RADIO2RXBUFF_RXDIS, packetNum);

% Disable the receiver radio
warplab_sendCmd(udp_node2, RADIO2_RXDIS, packetNum);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 5. Plot the transmitted and received data and close sockets
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
frequency_vector = d2phase_dt*t;
frequency_vector_RSSI = frequency_vector(1:4:end);
frequency_vector_RSSI = frequency_vector_RSSI(1:length(frequency_vector_RSSI));

figure;
subplot(2,2,1);
plot(real(Node1_Radio2_TxData));
title('Tx Node 1 Radio 2 I');
xlabel('n (samples)'); ylabel('Amplitude');
axis([0 2^14 -1 1]); % Set axis ranges.
subplot(2,2,2);
plot(imag(Node1_Radio2_TxData));
title('Tx Node 1 Radio 2 Q');
xlabel('n (samples)'); ylabel('Amplitude');
axis([0 2^14 -1 1]); % Set axis ranges.
subplot(2,2,3);
plot(real(Node2_Radio2_RxData));
title('Rx Node 2 Radio 2 I');
xlabel('n (samples)'); ylabel('Amplitude');
axis([0 2^14 -1 1]); % Set axis ranges.
subplot(2,2,4);
plot(imag(Node2_Radio2_RxData));
title('Rx Node 2 Radio 2 Q');
xlabel('n (samples)'); ylabel('Amplitude');
axis([0 2^14 -1 1]); % Set axis ranges.

figure;
subplot(2,2,1);
plot(frequency_vector,abs(Node2_Radio2_RxData));
title('Magnitude Rx Node 1 Radio 2');
xlabel('Frequency'); ylabel('Magnitude');
axis([0 20e6 -1 1]); % Set axis ranges.
subplot(2,2,2);
plot(abs(Node2_Radio2_RxData));
title('Magnitude Rx Node 1 Radio 2');
xlabel('n (samples)'); ylabel('Magnitude');
axis([0 2^14 -1 1]); % Set axis ranges.
subplot(2,2,3);
plot(frequency_vector_RSSI,Node2_Radio2_RSSIData);
title('Magnitude RSSI Node 1 Radio 2');
xlabel('Frequency'); ylabel('Magnitude');
axis([0 20e6 0 2^10]); % Set axis ranges.
subplot(2,2,4);
plot(Node2_Radio2_RSSIData);
title('Magnitude RRSSI Node 1 Radio 2');
xlabel('n (samples)'); ylabel('Magnitude');
axis([0 2^14 0 2^10]); % Set axis ranges.

% figure;
% subplot(2,1,1);
% plot(frequency_vector,abs(Node2_Radio2_RxData));
% title('Magnitude Rx Node 1 Radio 2');
% xlabel('Frequency'); ylabel('Magnitude');
% axis([0 20e6 -1 1]); % Set axis ranges.
% subplot(2,1,2);
% plot(abs(Node2_Radio2_RxData));
% title('Magnitude Rx Node 1 Radio 2');
% xlabel('n (samples)'); ylabel('Magnitude');
% axis([0 2^14 -1 1]); % Set axis ranges.
% 
% figure;
% subplot(2,1,1);
% plot(frequency_vector_RSSI,Node2_Radio2_RSSIData);
% title('Magnitude RSSI Node 1 Radio 2');
% xlabel('Frequency'); ylabel('Magnitude');
% axis([0 20e6 -1 1]); % Set axis ranges.
% subplot(2,1,2);
% plot(Node2_Radio2_RSSIData);
% title('Magnitude RSSI Node 1 Radio 2');
% xlabel('n (samples)'); ylabel('Magnitude');
% axis([0 2^14 -1 1]); % Set axis ranges.

% figure;
% subplot(2,2,1);
% plot(frequency_vector,real(Node1_Radio2_TxData));
% title('Tx Node 1 Radio 2 I');
% xlabel('Frequency'); ylabel('Magnitude');
% axis([0 20e6 -1 1]); % Set axis ranges.
% subplot(2,2,2);
% plot(frequency_vector,imag(Node1_Radio2_TxData));
% title('Tx Node 1 Radio 2 Q');
% xlabel('Frequency'); ylabel('Magnitude');
% axis([0 20e6 -1 1]); % Set axis ranges.
% subplot(2,2,3);
% plot(frequency_vector,real(Node2_Radio2_RxData));
% title('Rx Node 2 Radio 2 I');
% xlabel('Frequency'); ylabel('Magnitude');
% axis([0 20e6 -1 1]); % Set axis ranges.
% subplot(2,2,4);
% plot(frequency_vector,imag(Node2_Radio2_RxData));
% title('Rx Node 2 Radio 2 Q');
% xlabel('Frequency'); ylabel('Magnitude');
% axis([0 20e6 -1 1]); % Set axis ranges.


% figure;
% subplot(2,1,1);
% plot(frequency_vector,abs(Node1_Radio2_TxData));
% title('Magnitude Tx Node 1 Radio 2');
% xlabel('Frequency'); ylabel('Magnitude');
% axis([0 20e6 -1 1]); % Set axis ranges.
% subplot(2,1,2);
% plot(frequency_vector,abs(Node1_Radio2_TxData));
% title('Magnitude Rx Node 1 Radio 2');
% xlabel('Frequency'); ylabel('Magnitude');
% axis([0 20e6 -1 1]); % Set axis ranges.


% Close sockets
pnet('closeall');