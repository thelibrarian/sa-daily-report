#!/usr/bin/env ruby -w
=begin
Copyright (c) 2004-2005, Tony Kemp
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE 
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
POSSIBILITY OF SUCH DAMAGE.
=end

require 'zlib'
require 'date'
require 'net/smtp'

class Sorter
  
  def initialize
    # This is the directory where the quarantined emails are stored
    @directory = "/var/amavis/quarantine"
    @dateline = (Date.today - 1).strftime("%Y%m%d")
    @report_date = (Date.today - 1).strftime("%d/%m/%y")
    # This is the file pattern used to match the quarantined spam
    # emails in the quarantined email directory. This is used so that
    # only spam (and not virii etc.) from the report day are matched.
    @file_patt = "spam-*-#{@dateline}-*.gz"
    @spams = Array.new
    @report = ""
    # These two variables tell the script where to send the report.
    @to_name = "Root"
    @to_address = "root@example.com"
    # This is the server and port to use when sending the report email
    @server = "mail.example.com"
    @port = 25
  end

  def run
    scan_spam
    create_report
    mail_report
  end

  def scan_spam
    Dir.chdir(@directory)
    files = Dir[@file_patt]
    files.each { |filename|
      spam = Spam.new
      spam.filename = filename
      begin
        Zlib::GzipReader.open(filename) { |file|
          file.each_line { |line|
            spam.feed(line)
            break if spam.full?
          }
        }
      rescue Zlib::Error => error
        spam.error_message = error.message
      end
      @spams << spam
    }
  end

  def create_report
    @report += "Hello #{@to_name},\n\nHere is the summary of quarantined spam:\n\n"
    if @spams.size == 0
      @report += "Yay! No spam!\n"
    else
      @report += "There is a total of #{@spams.size} spam emails for #{@report_date}.\n\n"
      @spams.each { |spam|
        if spam.has_error?
          @report += "Error reading with file:\n  #{spam.filename}\n#{spam.error_message}\n"
        else
          @report += spam.from + spam.to + spam.subject + spam.sa_status
        end
        @report += "Quarantined as:\n#{spam.filename}\n\n"
      }
      @report += "Remember, these spams are quarantined in #{@directory}\n on spamfilter.primur.com\n"
    end
    @report += "\nRegards,\nspamfilter.\n"
  end

  def mail_report
    @report = mail_header + @report
    begin
      Net::SMTP.start(@server, @port) { |smtp|
        smtp.send_message @report, "root@spamfilter.primur.com", @to_address
      }
    rescue
    end
  end
        
  def mail_header
    header = "From: Spam Report <root@spamfilter.primur.com>\n"
    header += "To: #{@to_name} <#{@to_address}>\n"
    header += "Subject: Spam Report For #{@report_date}\n"
    header += "Message-ID: <spamreport-#{(DateTime.now).strftime("%y%m%d%H%M%S")}@spamfilter.primur.com>\n\n"
  end
end

class Spam
  attr_accessor :filename, :from, :to, :subject, :sa_status, :error_message
  attr_reader :re_from, :re_to, :re_subject, :re_sa_status

  def initialize
    @re_from = /^From: .*/
    @re_to = /^To: /
    @re_subject = /^Subject: .*/
    @re_sa_status = /^X-Spam-Status: .*/
    @count = 0;
    @error_message = nil
  end

  def feed(line)
    if line =~ re_from
      @from = line
    elsif line =~ re_to
      @to = line
    elsif line =~ re_subject
      @subject = line
    elsif line =~ re_sa_status
      @sa_status = line
    else
      return
    end
    @count += 1;
  end

  def full?
    @count == 4
  end

  def has_error?
    @error_message != nil
  end
end

my_sorter = Sorter.new
my_sorter.run
