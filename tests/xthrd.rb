

$stdout.sync = true

class Cache

  def resweep( period )
    Thread.new do
      begin

        #sleep( period )
        # unnecessary for the demo

        sweep_cache

      rescue
        puts $!
        exit 1
      end

      # then return, so we cease to exist, freeing our resources... right?
    end
  end


  def sweep_cache
    $stdout.write "."
    # look for when we need to schedule a new sweep
    # ... lets say we need to sweep in a second:

    resweep(1)

  end

end
    

c = Cache.new

c.resweep(1)

loop do
  sleep 60
end

