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

Instructions:
This script is designed to be run on a daily basis, i.e. as a cron job or
similar on a machine that is using amavisd-new and SpamAssassin to filter
incoming mail. This script is of use if you wish to recieve a report each 
day of all the emails that SpamAssassin has marked as spam and amavisd-new
has consequently quarantined in its quarantine directory, so that you can
check for false positives. The report consists of the 'To', 'From' and
'Subject' headers of each email, plus the spam score SpamAssassin gave it.

The only things that should need chaning below are:
  @directory - amavisd-new's quarantine directory.
  @to_name - the name of the person recieving the report
  @to_address - the email address the report is to be sent to
  @server - the outgoing SMTP server to use
And possibly:
  @port - the port the SMTP server is running on. 25 is the standard.

Once you have configured this script correctly you should then set up the 
cron job to run this each day. It scans all of the emails in the quarantine
directory from the previous day, so I usually run it at 1 a.m., so that the
report of yesterday's spam is waiting for me each morning.
=end

require 'zlib'
require 'date'
require 'net/smtp'

class Sorter
  
  def initialize
    # This is the directory where amavisd-new stores the quarantined emails.
    @directory = "/var/amavis/quarantine"
    @dateline = (Date.today - 1).strftime("%Y%m%d")
    @report_date = (Date.today - 1).strftime("%d/%m/%y")
    # This is the file pattern used to match the quarantined spam
    # emails in the quarantined email directory. This is used so that
    # only spam (and not virii etc.) from the report day are matched.
    @file_patt = "spam-*-#{@dateline}-*.gz"
    @spams = Array.new
    @report = ""
    # The name of the server hosting the mail filter
    @server_name = "mailfilter.example.com"
    # These two variables tell the script where to send the report.
    @to_name = "Root"
    @to_address = "root@example.com"
    # These two variables tell the script who the report email is 'from'.
    @from_name = "Spam Reporter"
    @from_address = "root@#{@servername}"
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
      @report += "Remember, these spams are quarantined in #{@directory}\n on #{@server_name}\n"
    end
    @report += "\nRegards,\nspamfilter.\n"
  end

  def mail_report
    @report = mail_header + @report
    begin
      Net::SMTP.start(@server, @port) { |smtp|
        smtp.send_message @report, @from_address, @to_address
      }
    rescue
    end
  end
        
  def mail_header
    header = "From: #{@from_name} <#{@from_address}>\n"
    header += "To: #{@to_name} <#{@to_address}>\n"
    header += "Subject: Spam Report For #{@report_date}\n"
    header += "Message-ID: <spamreport-#{(DateTime.now).strftime("%y%m%d%H%M%S")}@#{@server_name}>\n\n"
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
    case line
    when re_from
      @from = line
    when re_to
      @to = line
    when re_subject
      @subject = line
    when re_sa_status
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
