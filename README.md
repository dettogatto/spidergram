# Spidergram

## Instructions

1) Edit the hashtags you are interested in in the `go.rb` file as a hash where the key is the hashtag and the value is how many posts from that hashtag you want to like (ex. `{love: 100}`).

2) In the main loop comment out the actions you dont't want to perform

3) Launch the `go.rb` file

## Actions

- `crawl(hash)` -> Crawls the hashtag pages of the passed in hash and places the likes.
- `funfollow(n)` -> Follows and unfollows accounts. `n` defines how many accounts you want to follow at a time, so `funfollow(0)` will unfollow every account previously followed by the bot, leaving your manually followed accounts intact.