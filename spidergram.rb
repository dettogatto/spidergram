require 'watir' # Crawler
require 'io/console'
require 'headless'
require_relative 'helper'
require_relative 'database'

class SpiderGram

	attr_reader :db

	include Helper
	MAX_TRIES = 50 #max tries to get the buttons (10tries ~= 1s)
	DEFAULT_LIKES_MAP = {
		parkour: 80,
		freerunning: 80,
		circus: 20,
		handstand: 20,
		acrobatics: 20,
		fitness: 50
	}

	def initialize(browser = "chrome", headless = false, browser_instances = 2, incognito = false)
		@db = SQLite3DB.new
		@headless = nil
		@bs = [nil] * browser_instances
		@init_browser = browser
		@init_headless = headless
		@incognito = incognito
		@isberry = false
		FileUtils.mkdir_p(File.dirname("./data/"))
		if @init_browser == "raspberry"
			@isberry = true
			@init_browser = "firefox"
			@init_headless = true
			@incognito = false
		end
	end


	def ask_for_login_data
		data = @db.get_login_data
		if data
			@username, @password = data
		else
			putf "Insert username"
			@username = encode(gets.chomp)
			putf "Insert password"
			@password = encode(STDIN.noecho(&:gets).chomp)
      ans = ""
      while ans != "y" && ans != "n"
        putf "Should I remember those? (y/n)"
        ans = gets.chomp.downcase
      end
      if ans == "y"
        @db.set_login_data(decode(@username), decode(@password))
        putf "Won't forget!"
      else
        putf "Okay boss."
      end
		end
	end


	def go
		if @init_headless
			@headless = Headless.new
			@headless.start
		end
		putf "Opening browser #{@init_browser.capitalize}"

		if @isberry
			@bs.map!{ Watir::Browser.new @init_browser.to_sym, profile: 'default' }
			putf "Using default profile"
		else
			if @incognito
				@bs.map!{ Watir::Browser.new @init_browser.to_sym, switches: ['--incognito'] }
			else
				@bs.map!{ Watir::Browser.new @init_browser.to_sym}
			end
		end

		puts ""
		# Try to log in or re-ask data
		ask_for_login_data
		login
	end


	def close
		stop
	end
	def stop
		putf "Closing browsers"
		@bs.each do |b|
			begin
				b.close if b
			rescue Net::ReadTimeout => e
				putf "Seems to be taking a while..."
				sleep(10)
			end
		end
		@bs.map!{ |_| nil }
		if @headless
			putf "Destroying headless session"
			@headless.destroy
		end
		putf "Stopped"
	end


	def login
		c = 1
		success = false
		@bs.each do |b|
			putf "Going to Insta with instance #{c}"
			begin
				b.goto "instagram.com"
			rescue Net::ReadTimeout => e
				putf "Seems to be taking a while..."
				sleep(10)
			end
			# Check for a like button to see if I'm logged
			the_like = get_element(b, tag_name: "button", class: "coreSpriteHeartOpen")
			if the_like # If already logged
				putf "Already logged in :D"
				success = true
			else
				if @isberry
					putf "You are not logged in and I won't try to"
					break
				end
				begin
					b.goto "instagram.com/accounts/login/"
				rescue Net::ReadTimeout => e
					putf "Seems to be taking a while..."
					sleep(10)
				end
				sleep(5)
				putf "Logging in with instance #{c}..."
				b.text_field(:name => "username").set(decode(@username))
				b.text_field(:name => "password").set(decode(@password))
				b.button(:text => "Log In").click
				sleep(5)
				success = !(/login/i === b.url)
				putf (success ? "Logged in with instance #{c}!" : "Something went wrong... Try again!")
				break if !success
			end
			c += 1
		end
		success
	end


	######  CRAWLING  ######


	def crawl(likes_map = DEFAULT_LIKES_MAP)
		if @bs.all?{ |i| !i }
			go
			sleep(10)
		end
		loop do
			all_done = true
			likes_map.to_a.shuffle.to_h.each do |key, val|
				al = @db.liked_today(key.to_s)
				putf "Liked #{al} out of #{val} of ##{key}"
				next if al >= val
				all_done = false
				# begin
					like_hashtags({key => [val-al, 30].min})
				# rescue Exception => e
				# 	putf "Got #{e.class} exception: restarting browser"
				# 	puts "", e.backtrace, ""
				# 	log e.backtrace
				# 	stop
				# 	sleep(10)
				# 	go
				# 	sleep(10)
				# end
			end
			break if all_done
		end
	end


	def like_hashtags(likes_map = DEFAULT_LIKES_MAP, wait = true)
		likes_map.each do |tag, lks|
			putf "Liking #{lks} posts of ##{tag}"
			tag = tag.to_s
			lks_given = 0  # ToDo(?): Initialize to already given likes today
			goto_hashtag(@bs.first, tag)
			click_first_post(5)
			c = 0
			loop do
				liked = like_one
				(puts ""; break) if !liked
				lks_given += liked
				heart = "AL"
				if liked == 1
					heart = "<3"
					@db.like(tag)
					save_user_data(get_post_owner, tag) if @bs.size > 1
				end
				print "  #{heart}"
				random_sleep if wait && liked == 1
				puts "" if c == 4
				(puts ""; break) if lks_given >= lks
				(puts ""; break) if !goto_next_post
				c = (c + 1) % 5
			end
		end
		print_likes_report(1)
	end


	######  DOING STUFF  ######

  def random_sleep()
    sleep((50..200).to_a.sample.to_f / 100)
  end

	def like_one(b = @bs[0]) # Return 1: liked, 0: already liked, false: error occurred
		the_like = get_element(b, tag_name: "button", class: "afkep")
		the_glyphs = get_elements(b, tag_name: "span", class: /glyphsSpriteHeart/i)
		return false if !the_like || !the_glyphs || the_glyphs.empty?
		already_liked = (/filled/ === the_glyphs.last.class_name)
		if !already_liked
			if click_element(the_like)
				return 1
			else
				return false
			end
		end
		0
	end

	def funfollow(users = 100)
		report = @db.funfollow_report(1)
		followed_today = report[0][:followed]
		follow(users - followed_today) if users > followed_today
		curr_foll = @db.currently_following
		unfollow(curr_foll - users) if curr_foll > users
		tot = @db.currently_following
		putf "Currently following #{tot}"
		tot
	end

	def follow(users = 1)
		tot = 0
		loop do
			# begin
				u = @db.followables(1)
				break if u.empty?
				u = u[0]
				goto_user(@bs.first, u)
				if follow_user
					@db.follow(u)
					putf "Followed @#{u}"
					tot += 1
				else
					putf "Could not follow @#{u} :("
					@db.delete_grammer(u)
				end
				break if tot >= users && users > 0
				sleep(2)
			# rescue Exception => e
			# 	putf "Got #{e.class} exception: restarting browser"
			# 	puts "", e.backtrace, ""
			# 	log e.backtrace
			# 	stop
			# 	sleep(10)
			# 	go
			# 	sleep(10)
			# end
		end
		putf "Total followed: #{tot}" if users != 1
		tot
	end

	def unfollow(users = 0)
		tot = 0
		fol = get_following
		us = fol.select{ |i| @db.unfollowed?(i) }
		putf("To re-unfollow:")
		puts us * ", " if us.any?
		puts("ToT:  #{us.size}")
		us.each do |u|
			goto_user(@bs.first, u)
			if unfollow_user
				@db.unfollow(u)
				putf "Unfollowed @#{u}"
				tot += 1
			else
				putf "Could not unfollow @#{u} :("
			end
			sleep(1)
		end
		putf "Total unfollowed: #{tot}" if users != 1
		tot
	end

	def follow_user(b = @bs[0])
		the_follow = get_element(b, tag_name: "button", text: /Follow/i)
		a = click_element(the_follow)
		sleep(0.3)
		a
	end

	def unfollow_user(b = @bs[0])
		the_unfollow = get_element(b, tag_name: "button", visible_text: /Following/i)
		return false if !click_element(the_unfollow)
		sleep(0.5)
		the_unfollow = get_element(b, tag_name: "button", visible_text: /Unfollow/i)
		a = click_element(the_unfollow)
		sleep(0.3)
		a
	end

	def click_element(el)
		return false if !el
		begin
			el.click!
			return true
		rescue Exception => e
			putf "OUCH! missed a button!"
			return false
		end
	end


	######  NAVIGATING  ######

	def goto_user(b, user)
		putf "Going to @#{user}" if b == @bs.first
		b.goto("instagram.com/#{user}/")
	end

	def goto_post(b, post)
		b.goto("instagram.com/p/#{post}")
	end

	def goto_hashtag(b, tag)
		putf "Going to ##{tag}" if b == @bs.first
		b.goto("instagram.com/explore/tags/#{tag}")
	end

	def click_first_post(skips = 0)
		putf "Clicking post number #{skips+1}"
		posts = get_elements(@bs.first, tag_name: "div", class: "eLAPa")
		post = posts[[skips, posts.size-1].min]
		post.click! if post
		!!post
	end

	def goto_next_post()
		last = get_post_description
		nxt = get_element(@bs.first, tag_name: "a", class: /coreSpriteRightPaginationArrow/i)
		if nxt
			nxt.click!
		else
			puts "######  " + "OUCH! Can't go to next post!"
			return false
		end
		end_of_loop = MAX_TRIES.times do |i|
			#wait for the new post to actually load
			sleep(0.2)
			break if get_post_description && get_post_description != last
			nxt.click! if i == 20
		end
		return !end_of_loop
	end




	######  COLLECTING USER DATA  ######

	def save_user_data(user, hashtags = "")
		data = get_user_data(user, hashtags)
		if data
			return @db.sync(data)
		end
		false
	end

	def get_user_data(user, hashtags = "")
		goto_user(@bs[1], user)
		return nil if user_private?(@bs[1])
		{
			username: user,
			n_posts: get_user_posts(@bs[1]),
			n_followers: get_user_followers(@bs[1]),
			n_following: get_user_following(@bs[1]),
			t_follow: (do_i_follow?(@bs[1]) ? 1 : 0),
			hashtags: hashtags
		}
	end

	def get_user_posts(b = @bs[0])
		sleep(0.01)
		txt = get_element(b, tag_name: "span", class: "-nal3", visible_text: /(post)[s]?/i)
		txt ? instastr_to_i(txt.text) : nil
	end

	def get_user_followers(b = @bs[0])
		sleep(0.01)
		txt = get_element(b, tag_name: "a", class: "-nal3", visible_text: /followers/i)
		txt ? instastr_to_i(txt.text) : nil
	end

	def get_user_following(b = @bs[0])
		sleep(0.01)
		txt = get_element(b, tag_name: "a", class: "-nal3", visible_text: /following/i)
		txt ? instastr_to_i(txt.text) : nil
	end

	def get_user_bio(b = @bs[0])
		sleep(0.01)
		txt = get_element(b, tag_name: "div", class: "-vDIg")
		txt ? txt.text : nil
	end

	def user_private?(b = @bs[0])
		sleep(0.01)
		b.element(tag_name: "h2", class: "rkEop", visible_text: /account is private/i).exist?
	end

	def do_i_follow?(b = @bs[0])
		sleep(0.01)
		txt = get_element(b, tag_name: "button", class: "_5f5mN", visible_text: /follow/i)
		txt ? (/following/i === txt.text) : nil
	end

	def get_post_description(b = @bs[0])
		sleep(0.01)
		txt = get_element(b, tag_name: "div", class: "C4VMK")
		txt ? txt.text : false
	end

	def get_post_owner(b = @bs[0])
		sleep(0.01)
		name = get_element(b, tag_name: "a", class: "FPmhX")
		name ? name.title : false
	end

	def get_following(b = @bs[0])
		putf "Going to @#{decode(@username)} page"
		goto_user(b, decode(@username))
		sleep(0.5)
		putf "Clicking following link"
		link = get_element(b, tag_name: "a", visible_text: /following/)
		if !link
			putf "Can't find the following link :("
			return false
		end
		link.click!
		sleep(1)
		gather_users_from_scrollbox(b)
	end

	def gather_users_from_scrollbox(b = @bs[0])
		lis = get_elements(b, tag_name: "li")
		last = 0
		curr = -1
		putf "Scrolling"
		loop do
			# I do the scrolling!
			30.times do
				begin
					b.execute_script("(document.getElementsByClassName('isgrP')[0]).scrollTo(0, #{last + 1000});")
				rescue Exception => e
					putf("Could not JS scroll")
				end
				begin
					lis.last.scroll_into_view
				rescue Exception => e
					putf("Could not Selenium scroll")
				end
				sleep(0.2)
				curr = b.execute_script("return (document.getElementsByClassName('isgrP')[0]).scrollTop;")
				break if curr != last
				lis = get_elements(b, tag_name: "li")
			end
			break if last == curr
			last = curr
		end
		putf "Gathering followers names"
		get_elements(b, tag_name: "a", class: "FPmhX").map(&:title)
	end


	######  GETTING HTML ELEMENTS  ######

	def get_element(b, hashmap, maxtries = MAX_TRIES)
		all = get_elements(b, hashmap, maxtries)
		all ? all.first : nil
	end

	def get_elements(b, hashmap, maxtries = MAX_TRIES)
		# returns the elements or nil if it can't find it
		el = nil
		return nil if maxtries.times do |i| # return nil if I can't find the element
				# Looking for the like button
				el = b.elements(hashmap)
				break if el[0].exist? # found it!
				sleep(0.1)
		end
		el
	end


	######  REPORTING  ######

	def plr(days = 5)
		@db.print_likes_report(days)
	end
	def print_likes_report(days = 5)
		@db.print_likes_report(days)
	end

	def print_funfollow_report(days = 5)
		@db.print_funfollow_report(days)
	end
	def pfr(days = 5)
		@db.print_funfollow_report(days)
	end



end
