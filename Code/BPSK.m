Es=1; %Energy Per Symbol
M=2; %Number of Transmitter=Receiver
Hw=sqrt(Es/2.0)*(randn(M)+j*randn(M));
N=10000; %Total No of Symbols Transmitted

Tx_signal=2.*randi(2,M,N)-3;

SNR=10;
    Rx_signal=awgn(Hw*Tx_signal,SNR,'measured');
    Detect=2*(real(Rx_signal(:,:))>0)-1;
    Error=sum(sum(Detect~=Tx_signal))/numel(Tx_signal);

