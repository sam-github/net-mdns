
require 'socket'

# mDNSexport void FindDefaultRouteIP(mDNSAddr *a)
# {
#   struct sockaddr_in addr;
#   socklen_t len = sizeof(addr);
#   int sock = socket(AF_INET,SOCK_DGRAM,0);
#   a->type = mDNSAddrType_None;
#   if (sock == -1) return;
#     addr.sin_family = AF_INET;
#     addr.sin_port = 1;    // Not important, any port and public address will do
#     addr.sin_addr.s_addr = 0x11111111;
#     if ((connect(sock,(const struct sockaddr*)&addr,sizeof(addr))) == -1) { close(sock); return; }
#     if ((getsockname(sock,(struct sockaddr*)&addr, &len)) == -1) { close(sock); return; }
#     close(sock);
#     a->type = mDNSAddrType_IPv4;
#     a->ip.v4.NotAnInteger = addr.sin_addr.s_addr;
#   }



s = UDPSocket.new
s.connect(Socket::INADDR_ANY, 1)
sain = s.getsockname

len, family, port, addr = sain.unpack 'CCnN'

p len, family, port, addr

p "%x" % addr

# struct sockaddr_in {
#   u_char  sin_len;
#   u_char  sin_family;   
#   u_short sin_port;
#   struct  in_addr sin_addr;
#   char  sin_zero[8];
# };
# 


