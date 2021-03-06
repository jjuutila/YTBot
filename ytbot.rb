# encoding: utf-8

require "twitter"
require "feedzirra"
require "yaml"
require "logger"
require "httparty"

SECONDS_BETWEEN_FEED_POLLING = 60

logger = Logger.new(File.join(__dir__, "log/ytbot.log"), 10, 1024000)
logger.datetime_format = "%Y-%m-%d %H:%M:%S"

def create_tweet_text title_without_source, url
  "#{title_without_source} #{url}"
end

def strip_news_source feed_entry
  news_source_tag_index = feed_entry.title.rindex("(")
  feed_entry.title.slice(0, news_source_tag_index).strip()
end

def maybe_create_entry text, created_at = Time.now
  m = /^(.+) aloittaa YT-neuvottelut/i.match(text)
  m ||= /^(.+) irtisanoo(.*)( +)(\d+)/i.match(text)
  if m
    {content: text, created_at: created_at, match: m[0]}
  else
    nil
  end
end

class EntryHistory
  def initialize initial_contents = [], max_size = 100
    @max_size = max_size
    @contents = initial_contents
  end

  def include_match? entry
    @contents.any? {|existing_entry| existing_entry[:match].downcase == entry[:match].downcase}
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

recent_entries = client.user_timeline.map{|tweet| maybe_create_entry(tweet.text, tweet.created_at)}.reject{|entry| entry.nil?}.take(20)
history = EntryHistory.new recent_entries
logger.info("Loaded #{recent_entries.length} tweets")
logger.info("Starting main loop")

while true do
  begin
    feed_or_error = Feedzirra::Feed.fetch_and_parse("http://feeds.feedburner.com/ampparit-kaikki-eibb")

    unless feed_or_error.is_a? Fixnum
      feed_or_error.entries.each_entry do |feed_entry|
        title_without_source = strip_news_source(feed_entry)
        entry = maybe_create_entry(title_without_source)
        if entry and !history.include_match?(entry)
          logger.info("Resolve redirect address: #{feed_entry.url}")
          url = HTTParty.get(feed_entry.url, {follow_redirects: false}).headers["location"]

          tweet_text = create_tweet_text(title_without_source, url)
          logger.info("Sending Twitter update: #{tweet_text}")
          client.update(tweet_text)
          history.push(entry)
        end
      end
    else
      logger.error("Fetching news feed failed with response code #{feed_or_error}")
    end
  rescue Twitter::Error => te
    logger.error("Sending Twitter update failed: #{te.message}")
  rescue => e
    logger.error("Unexpected error: \"#{e.message}\" stacktrace: #{e.backtrace}")
  ensure
    sleep(SECONDS_BETWEEN_FEED_POLLING)
  end
end
