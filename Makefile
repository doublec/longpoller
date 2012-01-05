INCLUDE=-I/usr/local/include
LIB=-L/usr/local/lib -levent -lcurl

all: longpoll

longpoll_sats.o: longpoll.sats
	atscc $(INCLUDE) -c $<

longpoll_dats.o: longpoll.dats longpoll.sats
	atscc $(INCLUDE) -c $<

main_dats.o: main.dats longpoll.dats longpoll.sats
	atscc $(INCLUDE) -c $<

longpoll: longpoll_sats.o longpoll_dats.o main_dats.o
	atscc $(INCLUDE) -o $@ $^ $(LIB)

clean:
	-rm *_dats.*
	-rm *_sats.*
	-rm longpoll
