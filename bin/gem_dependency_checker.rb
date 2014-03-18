#!/usr/bin/ruby
# Gem Dependency Checker
# Print out Gem/Gemspec/Gemfile dependencies, highlighting
# missing dependencies and those that are remotely
# available in various locations including koji,
# git, fedora, bodhi, rhn, etc.
#
# Pass -h to the script to see command line option details
#
# User is responsible for establishing authorization session
# before invoking this script
#
# Licensed under the MIT license
# Copyright (C) 2013-2014 Red Hat, Inc.
###########################################################

require 'optparse'
require 'colored'
require 'polisher/gem'
require 'polisher/gemfile'

##########################################################

conf = {:format            => nil,
        :gemfile           => './Gemfile',
        :gemspec           => nil,
        :gemname           => nil,
        :groups            => [],
        :devel_deps        => false,
        :highlight_missing => false,
        :check_fedora      => false,
        :check_git         => false,
        :check_koji        => false,
        :check_rhn         => false,
        :check_yum         => false,
        :check_bugzilla    => false,
        :check_errata      => false,
        :check_bodhi       => false}

optparse = OptionParser.new do |opts|
  opts.on('-h', '--help', 'Display this help screen') do
    puts opts
    exit
  end

  opts.on("--format val", 'Format which to render output') do |f|
    conf[:format] = f
  end

  opts.on('--gemfile file', 'Location of the gemfile to parse') do |g|
    conf[:gemfile] = g
  end

  opts.on('--group gemfile_groups', 'Gemfile groups (may be specified multiple times)') do |g|
    conf[:groups] << g
  end

  opts.on('--gemspec file', 'Location of the gemspec to parse') do |g|
    conf[:gemspec] = g
  end

  opts.on('--gem name', 'Name of the rubygem to check') do |g|
    conf[:gemname] = g
  end

  opts.on('--[no-]devel', 'Include development dependencies') do |d|
    conf[:devel_deps] = d
  end

  opts.on('-m', '--[no-]missing', 'Highlight missing packages') do |m|
    conf[:highlight_missing] = m
  end

  opts.on('-f', '--[no-]fedora', 'Check fedora for packages') do |f|
    conf[:check_fedora] = f
  end

  opts.on('-g', '--git [url]', 'Check git for packages') do |g|
    conf[:check_git] = g || "git://pkgs.fedoraproject.org/"
  end

  opts.on('-k', '--koji [url]', 'Check koji for packages') do |k|
    conf[:check_koji] = k || 'koji.fedoraproject.org/kojihub'
  end

  opts.on('-t', '--koji-tag tag', 'Koji tag to query') do |t|
    conf[:koji_tag] = t
  end

  opts.on('-b', '--bodhi [url]', 'Check Bodhi for packages') do |r|
    conf[:check_bodhi] = r || 'https://admin.fedoraproject.org/updates/'
  end

  opts.on('--rhn [url]', 'Check RHN for packages') do |r|
    conf[:check_rhn] = r || 'TODO'
  end

  opts.on('-y', '--yum', 'Check yum for packages') do |y|
    conf[:check_yum] = y
  end

  opts.on('-b', '--bugzilla', 'Check bugzilla for bugs filed against package') do |b|
    conf[:check_bugzilla] = b
  end

  opts.on('-e', '--errata [url]', 'Check packages filed in errata') do |e|
    conf[:check_errata] = e || nil
  end
end

optparse.parse!

if conf[:gemfile].nil? &&
   conf[:gemspec].nil? &&
   conf[:gemname].nil?

   if File.exists?('./Gemfile')
     conf[:gemfile] = './Gemfile'
   else
     puts "Valid Gemfile, GemSpec, or Gem must be specified".bold.red
     exit 1
   end
end

targets = []
targets << Polisher::VersionChecker::GEM_TARGET    if conf[:check_gem]
targets << Polisher::VersionChecker::KOJI_TARGET   if conf[:check_koji]
targets << Polisher::VersionChecker::FEDORA_TARGET if conf[:check_fedora]
targets << Polisher::VersionChecker::GIT_TARGET    if conf[:check_git]
targets << Polisher::VersionChecker::YUM_TARGET    if conf[:check_yum]
targets << Polisher::VersionChecker::BODHI_TARGET  if conf[:check_bodhi]
targets  = Polisher::VersionChecker::ALL_TARGETS   if targets.empty?
Polisher::VersionChecker.check targets

@format = conf[:format]

def format_dep(dep)
  if @format.nil?
    dep.to_s.blue.bold
  elsif @format == 'xml'
    "<#{dep}>"
  elsif @format == 'json'
    "'#{dep}':{"
  end
end

def format_end_dep(dep)
  if @format.nil?
    "\n"
  elsif @format == 'xml'
    "\n</#{dep}>"
  elsif @format == 'json'
    "\n}"
  end
end

def format_tgt(tgt)
  if @format.nil?
    "#{tgt.to_s.red.bold} "
  elsif @format == 'xml'
    "<#{tgt}/>"
  elsif @format == 'json'
    "'#{tgt}':null,"
  end
end

def format_tgt_with_versions(tgt, versions)
  if @format.nil?
    "#{tgt.to_s.green.bold}: #{versions.join(', ').yellow} "
  elsif @format == 'xml'
    "<#{tgt}>#{versions.join(', ')}</#{tgt}>"
  elsif @format == 'json'
    "'#{tgt}':['#{versions.join('\', \'')}'],"
  end
end

def print_header
  if @format == 'xml'
    puts '<dependencies>'
  elsif @format == 'json'
    puts '{'
  end
end

def print_footer
  if @format == 'xml'
    puts "</dependencies>"
  elsif @format == 'json'
    puts "}"
  end
end

def print_dep(tgt, dep, versions)
  # XXX little bit hacky but works for now
  @last_dep ||= nil
  if @last_dep != dep
    puts format_end_dep(@last_dep) unless @last_dep.nil?
    puts format_dep(dep)
    @last_dep = dep
  end

  if versions.nil? || versions.empty? ||
     versions.size == 1 && versions[0].nil?
    print format_tgt(tgt)
  else
    print format_tgt_with_versions(tgt, versions)
  end
end

print_header

if conf[:gemname]
  gem = Polisher::Gem.retrieve(conf[:gemname])
  gem.versions(:recursive => true, :dev_deps => true) do |tgt, dep, versions|
    print_dep(tgt, dep, versions)
  end

elsif conf[:gemspec]
  gem = Polisher::Gem.from_gemspec(conf[:gemspec])
  gem.versions(:recursive => true, :dev_deps => true) do |tgt, dep, versions|
    print_dep(tgt, dep, versions)
  end

elsif conf[:gemfile]
  gemfile = nil

  begin
    gemfile = Polisher::Gemfile.parse(conf[:gemfile], :groups => conf[:groups])
  rescue => e
    puts "Runtime err #{e}".red
    exit 1
  end

  gemfile.dependency_versions do |tgt, dep, versions|
    print_dep(tgt, dep, versions)
  end
end

puts format_end_dep(@last_dep) unless @last_dep.nil? # XXX
print_footer
