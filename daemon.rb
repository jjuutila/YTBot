require "rubygems"
require "daemons"

options = {
  :app_name   => "ytbot",
  :ARGV       => ["start", "-f"],
  :dir_mode   => :script,
  :dir        => "pids",
  :log_dir    => "logs",
  :multiple   => true,
  :ontop      => true,
  :backtrace  => true,
  :monitor    => true
}

Daemons.run("ytbot.rb", options)