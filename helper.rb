require 'fileutils'

module Helper

	FOLDER_DATA = File.expand_path("./data",  __dir__)

	def putf(str, indent = 0)
		puts "######  " + "  " * indent + str
	end

	def get_date_string
		tmp_date = Time.now.strftime("%Y%m%d%H%M")
	end

	def instastr_to_i(str)
		i = str.split[0]
		i.gsub!(?,, "")
		i.gsub!(/\.[0-9]{1}k/){ |i| i[1..-1].gsub(?k, "00") }
		i.gsub!(?k, "000")
		i.gsub!(/\.[0-9]{1}m/){ |i| i[1..-1].gsub(?m, "00000") }
		i.gsub!(?m, "000000")
		i.to_i
	end

	def encode(str)
		a = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
		b = "j8NUiW1VOaErIlDpeTfbtzCL4q5B9Zd2gnHxJQPFmcvAYhMGRKs6o3yuwkX7S0"
		str.tr(a, b)
	end

	def decode(str)
		a = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
		b = "j8NUiW1VOaErIlDpeTfbtzCL4q5B9Zd2gnHxJQPFmcvAYhMGRKs6o3yuwkX7S0"
		str.tr(b, a)
	end

	def log(str)
		# File.open("log.txt", "a"){ |f| f.puts str, "", "" }
		false
	end


end
