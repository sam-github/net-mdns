
require 'timeout'
require 'thread'
require 'pp'

class TimeService
  def initialize(&proc)
    @thread = Thread.new do
      begin
        loop do
          sleep 1
          proc.call(Time.now)
        end
      ensure
        # cleanup?
      end
    end
  end

  def stop
    @thread.kill
  end
end


case 3
when 1
  collection = []

  svc = TimeService.new do |t|
    pp t
    collection << t
  end

  pp svc

  sleep 5

  pp collection

  svc.stop

when 2

  queue = Queue.new

  svc = TimeService.new do |t|
    queue.push(t)
  end

  begin
    timeout(5) do
      loop do
        pp queue.pop
      end
    end
  rescue Timeout::Error
  ensure
    svc.stop
  end

when 3

  collection

  svc = TimeService.new do |t|
    pp t
    collection = t
    return
  end

  sleep 3

  svc.stop

  pp collection

end

