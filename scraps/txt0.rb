#!/usr/local/bin/ruby18 -w

require 'pp.rb'

require 'resolv.rb'

d = "\000\000\204\000\000\000\000\005\000\000\000\000\002me\005local\000\000\001\200\001\000\000\000\360\000\004\300\250\003\003\005proxy\010_example\004_tcp\300\017\000!\200\001\000\000\000\360\000\010\000\000\000\000'\017\300\f\300$\000\020\200\001\000\000\000\360\000\000\t_services\a_dns-sd\004_udp\300\017\000\f\000\001\000\000\034 \000\002\300*\300*\000\f\000\001\000\000\034 \000\002\300$"

m =  Resolv::DNS::Message.decode( d )

pp m

# IP 192.168.123.154.5353 > 224.0.0.251.5353:  0*- [0q] 5/0/0
#   (Cache flush) A 192.168.3.3,
#   (Cache flush) SRV me.local.:9999 0 0,
#   (Cache flush) TXT,
#   PTR _example._tcp.local.,
#   PTR proxy._example._tcp.local. (139)
#         0x0000:  4518 00a7 f6b3 0000 ff11 a73b c0a8 7b9a  E..........;..{.
#         0x0010:  e000 00fb 14e9 14e9 0093 a7fe 0000 8400  ................
#         0x0020:  0000 0005 0000 0000 026d 6505 6c6f 6361  .........me.loca
#         0x0030:  6c00 0001 8001 0000 00f0 0004 c0a8 0303  l...............
                           t   IN       240    4 rdata....
#         0x0040:  0570 726f 7879 085f 6578 616d 706c 6504  .proxy._example.
#         0x0050:  5f74 6370 c00f 0021 8001 0000 00f0 0008  _tcp...!........
                    _ t  c p (  )  SRV   IN       240    8

#         0x0060:  0000 0000 270f c00c c024 0010 8001 0000  ....'....$......
                      0    0 9999 (  ) (  )  TXT   IN
#         0x0070:  00f0 0000 095f 7365 7276 6963 6573 075f  ....._services._
                    240    0    _  s e
                        ^^^^ rdata length
#         0x0080:  646e 732d 7364 045f 7564 70c0 0f00 0c00  dns-sd._udp.....
#         0x0090:  0100 001c 2000 02c0 2ac0 2a00 0c00 0100  ........*.*.....
#         0x00a0:  001c 2000 02c0 24                        ......$

#  @answer=
#   [[#<Resolv::DNS::Name: me.local.>,
#     240,
#     #<Resolv::DNS::Resource::Generic::Type1_Class32769:0x3189d4
#      @data="\300\250\003\003">],
#    [#<Resolv::DNS::Name: proxy._example._tcp.local.>,
#     240,
#     #<Resolv::DNS::Resource::Generic::Type33_Class32769:0x3186c8

#      @data="\000\000\000\000'\017\300\f">],
                 0   0   0   0    f     c
#    [#<Resolv::DNS::Name: proxy._example._tcp.local.>,
#     240,
#     #<Resolv::DNS::Resource::Generic::Type16_Class32769:0x318344 @data="">],

TXT

#    [#<Resolv::DNS::Name: _services._dns-sd._udp.local.>,
#     7200,
#     #<Resolv::DNS::Resource::IN::PTR:0x3180b0
#      @name=#<Resolv::DNS::Name: _example._tcp.local.>>],
#    [#<Resolv::DNS::Name: _example._tcp.local.>,
#     7200,
#     #<Resolv::DNS::Resource::IN::PTR:0x317c28
#      @name=#<Resolv::DNS::Name: proxy._example._tcp.local.>>]],

