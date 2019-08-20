require_relative "spidergram"
# use "raspberry" as browser if you want to run on rpi
b = SpiderGram.new("chrome", false, 1)
f = 0
h = {
	love: 250,
	live: 120,
	laugh: 100
}
#puts h.values.reduce(:+)
hmezzo = h.map{|k, v| [k, v/2]}.to_h
loop do
	begin
		b.go
		b.funfollow(f)
		b.crawl(h)
		b.stop
	rescue Interrupt => e
    puts ""
		puts "######  Got interrupt. Arresting."
		b.stop
		break
	rescue Exception => e
    puts ""
		puts "######  Got an Exception, handling in main go.rb loop"
		b.stop
		next
	end
	sleep(60*60)
end
puts "######  Bye bye"
