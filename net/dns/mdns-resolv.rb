# Requiring 'net/dns/mdns-resolv' causes a Resolv::MDNS resolver to be added to
# list of default resolvers queried when using Resolv#getaddress, and the other
# Resolv module methods.

require 'net/dns/mdns.rb'

class Resolv
  # This is a bit of hack, but I want MDNS to be after Hosts, but it can't be
  # at the end because DNS throws an error if it fails a lookup.  This is fixed
  # in the latest CVS, but for now we need to be before DNS.
  DefaultResolver.resolvers.insert(-2, Resolv::MDNS.new)
end

