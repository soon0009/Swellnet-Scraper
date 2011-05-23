#!/usr/bin/env ruby
require 'rubygems'
require 'open-uri'
require 'nokogiri'
require 'net/smtp'
require 'net/http'
require 'tlsmail'
require 'sanitize'
require 'fileutils'
require 'yaml'

module SwellnetScraper
  DEBUG = true.freeze

  @@settings = nil
  def self.settings
    @@settings || begin
      YAML.load_file(File.join(File.dirname(__FILE__), 'settings.yml'))['settings']
    end
  end

  def self.swellnet_pages
    YAML.load_file(File.join(File.dirname(__FILE__), 'swellnet_pages.yml'))['swellnet_pages']
  end

  @@surfers = nil
  def self.surfers
    @@surfers || begin
      YAML.load_file(File.join(File.dirname(__FILE__), 'surfers.yml'))['surfers']
    end
  end

  def self.run
    raise "Your settings.yml file is missing" unless File.exists?(File.join(File.dirname(__FILE__), 'settings.yml'))
    raise "Your swellnet_pages.yml file is missing" unless File.exists?(File.join(File.dirname(__FILE__), 'swellnet_pages.yml'))
    raise "Your surfers.yml file is missing" unless File.exists?(File.join(File.dirname(__FILE__), 'surfers.yml'))
    swellnet_pages.each do |page|
      doc = ''
      Net::HTTP::Proxy(settings['proxy']['host'],
                       settings['proxy']['port'],
                       settings['proxy']['user'],
                       settings['proxy']['password']).start(page['host']) { |http|
        doc = Nokogiri::HTML(http.request_get(page['path']).read_body)
      }

      content = '';
      email_subject = page['descr']
      doc.css('ul.reportstats > li').each do |reportstats_item|
        content += Sanitize.clean(reportstats_item.to_s).gsub!(/\n/, " ").gsub(/\s+/, " ").gsub(/(\w+:)/, '\1') + "\n"
      end
      email_subject += " #{$~[1]}" if /(Rating\:.*)\n/.match(content)
      email_subject += " #{$~[1]}" if /(Surf\:.*)\n/.match(content)
      email_subject += settings['program_email']['append_to_subject'].to_s

      doc.css('ul.reportstats').each do |reportstats|
        content += "\n" + Sanitize.clean(reportstats.next_sibling.children.first.to_s)
      end

      if is_updated?(page['slug'], content)
        surfers.each do |surfer|
          send_email(settings['program_email']['email_address'], surfer['email'], email_subject, content) if surfer['swellnet_pages'].include? page['slug']
        end 
      end
    end
  end

  def self.send_email(from, to, subject, message)

msg = <<END_OF_MESSAGE
From: #{from}
To: #{to}
Subject: #{subject}
MIME-Version: 1.0

 #{message}
END_OF_MESSAGE

    if DEBUG
      puts "##############"
      puts from
      puts to
      puts subject
      puts msg
    else
      Net::SMTP.enable_tls(OpenSSL::SSL::VERIFY_NONE) if settings['program_email']['tls']
      Net::SMTP.start(settings['program_email']['mail_server'],
                      settings['program_email']['mail_port'],
                      'localhost',
                      settings['program_email']['login'],
                      settings['program_email']['password'],
                      settings['program_email']['auth_type'] ? settings['program_email']['auth_type'].to_sym : nil) do |smtp|
        smtp.send_message msg, from, to
      end
    end

  end

  def self.is_updated?(page_name, content)
    file_location = settings['tmp_dir'] + page_name
    tmp_file_location = settings['tmp_dir'] + page_name + '.tmp'
    if File.exists?(file_location)
      tmp_f = File.new(tmp_file_location, 'w+')
      tmp_f.puts(content)
      tmp_f.close()

      updated = if FileUtils.compare_file(file_location, tmp_file_location)
                  File.unlink(tmp_file_location)
                  false
                else
                  FileUtils.mv(tmp_file_location, file_location)
                  true
                end
      updated
    else
      f = File.new(file_location, 'w+')
      f.puts(content)
      true
    end
  end
end

SwellnetScraper.run
