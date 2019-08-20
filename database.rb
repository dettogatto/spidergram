require 'sqlite3'
require_relative 'helper'

class SQLite3DB

	attr_accessor :db

	include Helper

	FIELDS = %w(username n_posts n_followers n_following follows_me t_follow t_unfollow hashtags)

	def initialize
		@db = SQLite3::Database.open FOLDER_DATA + "/" + "data.db"
		@db.results_as_hash = true
		@db.execute "CREATE TABLE IF NOT EXISTS Grammers(
			username TEXT PRIMARY KEY NOT NULL UNIQUE,
			n_posts INTEGER,
			n_followers INTEGER,
			n_following INTEGER,
			follows_me INTEGER,
			t_follow INTEGER,
			t_unfollow INTEGER,
			hashtags TEXT
		)"
		@db.execute "CREATE TABLE IF NOT EXISTS LikesGiven(
			hashtag TEXT NOT NULL,
			date INTEGER NOT NULL,
			likes INTEGER,
			PRIMARY KEY (hashtag, date)
		)"
		@db.execute "CREATE TABLE IF NOT EXISTS Settings(
			name TEXT PRIMARY KEY NOT NULL UNIQUE,
			value TEXT
		)"
	end

	def like(hashtag, likes = 1)
		today = Date.today.to_time.to_i
		curr = @db.execute("SELECT likes from LikesGiven WHERE date = #{today} AND hashtag = '#{hashtag}' LIMIT 1")
		if curr.empty?
			@db.execute("INSERT INTO LikesGiven VALUES('#{hashtag}', #{today}, #{likes})")
		else
			curr = curr.first["likes"]
			@db.execute("UPDATE LikesGiven SET likes = #{curr + likes} WHERE date = #{today} AND hashtag = '#{hashtag}'")
		end
	end

	def grammers(n = 50)
		limit = (n > 0 ? "LIMIT #{n}" : "")
		@db.execute("SELECT * from Grammers #{limit}")
	end
	def likes(n = 50)
		limit = (n > 0 ? "LIMIT #{n}" : "")
		@db.execute("SELECT * from LikesGiven #{limit}")
	end



	def sync(user_data)
		user = {}
		FIELDS.each{ |f| user[f.to_sym] = (user_data[f.to_sym] || nil) }

		# Check for valid username
		return nil if !user[:username]

		# Check if already in DB
		old = @db.execute("SELECT * FROM Grammers WHERE username = '#{user[:username]}' LIMIT 1")
		if old.any?
			hashtags = old[0]["hashtags"]
			user[:hashtags] = (user[:hashtags].to_s + " " + hashtags.to_s).split.uniq.sort.join(" ")
			to_set = []
			to_set << "n_posts = #{user[:n_posts]}" if user[:n_posts]
			to_set << "n_followers = #{user[:n_followers]}" if user[:n_followers]
			to_set << "n_following = #{user[:n_following]}" if user[:n_following]
			to_set << "follows_me = #{user[:follows_me]}" if user[:follows_me]
			to_set << "hashtags = '#{user[:hashtags]}'" if user[:hashtags]
			query = "UPDATE Grammers SET #{to_set * ", "} WHERE username = '#{user[:username]}'"
			begin
				@db.execute(query)
			rescue Exception => e
				puts e
				return false
			end
		else
			arr = user.values.map do |v|
				if v
					v = "'#{v}'" if v.class == String
				else
					v = "NULL"
				end
				v
			end

			begin
				@db.execute("INSERT INTO Grammers VALUES(#{arr * ", "})")
			rescue Exception => e
				puts e
				return false
			end
		end

		return true
	end

	def remove(username)
		delete(username)
	end

	def delete(username)
		begin
			return @db.execute("DELETE FROM Grammers WHERE username = '#{username}'")
		rescue Exception => e
			puts e
			return false
		end
	end

	def liked_today(hashtag)
		res = @db.execute("SELECT likes from LikesGiven WHERE date = #{Date.today.to_time.to_i} AND hashtag = '#{hashtag}' LIMIT 1")
		res.any? ? res[0]["likes"] : 0
	end

	def likes_report(days = 5)
		res = []
		day = Date.today
		days.times do |i|
			likes = @db.execute("SELECT * from LikesGiven WHERE date = #{day.to_time.to_i}")
			res << {}
			likes.each do |l|
				res[-1][l["hashtag"]] = l["likes"]
			end
			day = day.prev_day
		end
		res.reverse
	end

	def funfollow_report(days = 5)
		res = []
		day = Date.today
		days.times do |i|
			followed = @db.execute("SELECT count(*) from Grammers WHERE t_follow > #{day.to_time.to_i} AND t_follow <= #{day.to_time.to_i+24*60*60}")
			unfollowed = @db.execute("SELECT count(*) from Grammers WHERE t_unfollow > #{day.to_time.to_i} AND t_unfollow <= #{day.to_time.to_i+24*60*60}")
			res << {followed: followed[0][0], unfollowed: unfollowed[0][0]}
			day = day.prev_day
		end
		res.reverse
	end

	def print_likes_report(days = 5)
		report = likes_report(days)
		total = report.map{ |r| r.map{|k, v| v} }.flatten.compact.reduce(:+)
		report.size.times do |i|
			putf "Liked #{i == report.size-1 ? "today" : "#{report.size - i - 1} days ago"}"
			if report[i].empty?
				putf "No data\n\n", 1
				next
			end
			report[i].each{ |k, v| putf("[#{v.to_s.rjust(total.to_s.size, " ")}]   ##{k}", 1) }
			t = report[i].map{ |k, v| v }.reduce(:+)
			putf("[#{t.to_s.rjust(total.to_s.size, " ")}]   total", 1)
			puts ""
		end
		(putf "Grand total: #{total}"; puts "") if days > 1
	end

	def print_funfollow_report(days = 5)
		report = funfollow_report(days)
		puts ""
		days.times do |i|
			putf "#{i == report.size-1 ? "Today" : "#{report.size - i - 1} days ago"}"
			puts "#{report[i][:followed].to_s.rjust(3, " ")}  followed"
			puts "#{report[i][:unfollowed].to_s.rjust(3, " ")}  unfollowed"
			puts ""
		end
		putf "Currently following:   #{currently_following}"
	end

	def currently_following
		@db.execute("
			SELECT count(*) FROM Grammers
			WHERE
				t_follow > 1 AND
				(t_unfollow IS NULL OR t_unfollow < t_follow)
		")[0][0]
	end


	def follow(username)
		now = Time.now.to_i
		@db.execute("UPDATE Grammers SET t_follow = #{now} WHERE username = '#{username}'")
		user_exist?(username)
	end

	def unfollow(username)
		now = Time.now.to_i
		@db.execute("UPDATE Grammers SET t_unfollow = #{now} WHERE username = '#{username}'")
		user_exist?(username)
	end

	def user_exist?(username)
		r = @db.execute("SELECT username FROM Grammers WHERE username = '#{username}'")
		r.any?
	end

	def search_grammers(username)
		r = @db.execute("SELECT * FROM Grammers WHERE username LIKE '%#{username}%'")
		print_grammers(r)
	end

	def followables(limit = 0)
		limit = limit.to_i
		l = (limit > 0 ? "LIMIT #{limit}" : "")
		r = @db.execute("
			SELECT username FROM Grammers
			WHERE
				(t_follow = 0 OR t_follow IS NULL) AND
				n_followers <= 1000000 AND
				n_followers > 40 AND
				n_following <= 2000 AND
				n_posts > 5
			#{l}
		")
		r.map{ |h| h["username"] }
	end

	def delete_grammer(user)
		@db.execute("DELETE FROM Grammers WHERE username = '#{user}'")
	end

	def followed(limit = 0)
		unfollowables(limit)
	end
	def unfollowables(limit = 0)
		limit = limit.to_i
		l = (limit > 0 ? "LIMIT #{limit}" : "")
		r = @db.execute("
			SELECT username FROM Grammers
			WHERE
				t_follow > 1 AND
				(t_unfollow IS NULL OR t_unfollow < t_follow)
			ORDER BY
				t_follow ASC
			#{l}
		")
		r.map{ |h| h["username"] }
	end

	def unfollowed?(username)
		r = @db.execute("SELECT * FROM Grammers WHERE username = '#{username}'")
		return nil if r.empty?
		r[0]["t_unfollow"] && r[0]["t_follow"] > 1 && r[0]["t_unfollow"] > r[0]["t_follow"]
	end

	def unfollowed(limit = 0)
		limit = limit.to_i
		l = (limit > 0 ? "LIMIT #{limit}" : "")
		r = @db.execute("
			SELECT username FROM Grammers
			WHERE
				t_follow > 1 AND
				t_unfollow IS NOT NULL AND
				t_unfollow > t_follow
			ORDER BY
				t_follow ASC
			#{l}
		")
		r.map{ |h| h["username"] }
	end

	def print_grammers(s = nil)
		s = grammers if !s
		s.each{|h|
			top = []
			h.each{|k, v|
				break if k == 0
				top << "#{k}(#{v})"
			}
			puts "", top * ", ", ""
		}
		true
	end

	def set_login_data(username, password)
		@db.execute("DELETE FROM Settings WHERE name = 'username' OR name = 'password'")
		@db.execute("INSERT INTO Settings VALUES('username', '#{encode(username)}')")
		@db.execute("INSERT INTO Settings VALUES('password', '#{encode(password)}')")
	end

	def delete_login_data()
		@db.execute("DELETE FROM Settings WHERE name = 'username' OR name = 'password'")
	end

	def get_login_data
		#data = @db.execute("SELECT value from Settings WHERE name = 'username' OR name = 'password'")
		us = @db.execute("SELECT value from Settings WHERE name = 'username'")
		pa = @db.execute("SELECT value from Settings WHERE name = 'password'")
		return nil if us.empty? || pa.empty?
		[us[0]["value"], pa[0]["value"]]
	end

end
