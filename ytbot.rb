# encoding: utf-8

require "twitter"
require "feedzirra"
require "yaml"
require "logger"

SECONDS_BETWEEN_FEED_POLLING = 60

logger = Logger.new(File.join(__dir__, "log/ytbot.log"), 10, 1024000)
logger.datetime_format = "%Y-%m-%d %H:%M:%S"

def remove_source_name title
  index = title.rindex("(")
  title.slice(0, index).strip()
end

class EntryHistory
  def initialize max_size = 100
    @max_size = max_size
    @contents = []
  end

  def include_title? title
    @contents.any? {|entry| entry[:title] == title}
  end

  def push entry
    if @contents.length == @max_size
      @contents.shift
    end

    @contents.push(entry)
  end
end

options = YAML::load_file(File.join(__dir__, "config.yml"))
client = Twitter::REST::Client.new do |config|
  config.consumer_key        = options["consumer_key"]
  config.consumer_secret     = options["consumer_secret"]
  config.access_token        = options["access_token"]
  config.access_token_secret = options["access_token_secret"]
end

history = EntryHistory.new

logger.info("Starting main loop")

while true do
  begin
    feed = Feedzirra::Feed.fetch_and_parse("http://feeds.feedburner.com/ampparit-kaikki-eibb")

    feed.entries.each_entry do |entry|
      titleWithoutSource = remove_source_name(entry.title)

      if entry.title.downcase.include?("aloittaa yt-neuvottelut") && !history.include_title?(titleWithoutSource)
        tweet_content = "#{titleWithoutSource} #{entry.url}"
        logger.info("Sending Twitter update: #{tweet_content}")
        client.update(tweet_content)
        posted_entry = {title: titleWithoutSource, url: entry.url, posted_at: DateTime.now}
        history.push(posted_entry)
      end
    end
  rescue Twitter::Error::ClientError => te
    logger.error("Sending Twitter update failed: #{te.message}")
  rescue Exception => e
    logger.error("Unexpected error: \"#{e.message}\" stacktrace: #{e.backtrace}")
  ensure
    sleep(SECONDS_BETWEEN_FEED_POLLING)
  end
end
