all: longpoll

longpoll_sats.o: longpoll.sats
	atscc -I/usr/local/include -c longpoll.sats

longpoll_dats.o: longpoll.dats
	atscc -I/usr/local/include -c longpoll.dats

main_dats.o: main.dats
	atscc -I/usr/local/include -c main.dats

longpoll: longpoll_sats.o longpoll_dats.o main_dats.o
	atscc -I/usr/local/include -o $@ $^ -L/usr/local/lib -levent -lcurl

clean:
	-rm longpoll_dats.*
	-rm longpoll_sats.*
	-rm main_dats.*
	-rm longpoll
