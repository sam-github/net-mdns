require 'thread'
require 'pp'

$stdout.sync = true

$lock = Mutex.new

$thrd = Thread.new do
    loop do
      $lock.synchronize do
        puts "sleep at #{Time.now}"
      end
      sleep( 5 )
    end
  end

r=(1..10)

r.each do |s|
    $lock.synchronize do
      puts "waker #{s} thrd"
    end

    sleep(s)

    $lock.synchronize do
      puts "wake thrd"
      $thrd.wakeup
    end
  end

