#!/usr/local/bin/ruby -w
=begin

sa-daily-report.rb release 1.1

License

Copyright (c) 2004-2006, Tony Kemp <tony.kemp@gmail.com>
Copyright (c) 2007, Tony Kemp <tony.kemp@gmail.com> & 
                    Juergen Dankoweit <Juergen.Dankoweit@FreeBSD-Onkel.de>
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
require 'mail'
require 'mail/parsers/content_type_parser'
## this is to check the encoding (https://github.com/brianmario/charlock_holmes)
require 'charlock_holmes'

class Sorter
  
  def initialize
    # This is the directory where amavisd-new stores the quarantined emails.
    @directory = "/var/virusmails"
    # @report_date = (Date.today - 1).strftime("%d/%m/%y")
    @report_date = (DateTime.now).strftime("%d.%m.%Y at %H:%M:%S (%Z)")
    # This is the file pattern used to match the quarantined spam
    # emails in the quarantined email directory. This is used so that
    # only spam (and not virii etc.) are matched.
    @file_patt = "spam-*.gz"
    # This file pattern will match only those spam emails received
    # on the previous day, if your spam filter puts the date in the filename.
    # @dateline = (Date.today - 1).strftime("%Y%m%d")
    # @file_patt = "spam-*-#{@dateline}-*.gz"
    @spams = Array.new
    @report = ""
    # The name of the server hosting the mail filter
    @server_name = ""
    # These two variables tell the script where to send the report.
    @to_name = "Root"
    @to_address = ""
    # These two variables tell the script who the report email is 'from'.
    @from_name = "Spam Reporter"
    @from_address = "root@#{@server_name}"
    # This is the server and port to use when sending the report email
    @server = ""
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
    # sorting on creation time of file "filename"
    files.sort! { |a,b|
      ac = Time.at(File.stat(a).ctime)
      bc = Time.at(File.stat(b).ctime)
      if ac == bc
        0
      else
        if ac < bc
          1
        else
          -1
        end
      end
    }
    files.each { |filename|
      spam = Spam.new
      spam.filename = filename
      begin
	gzip = Zlib::GzipReader.open(filename)
	gzip.each_line do |line|
	    spam.feed(line)
            break if spam.full?
	end
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
      # sorting for sender of mail
      @spams.sort! {|a,b|
        if a.mail_sender == b.mail_sender
          0
        else
          if a.mail_sender > b.mail_sender
            1
          else
            -1
          end
        end
      }
      @spams.each { |spam|
        if spam.has_error?
          @report += "Error reading with file:\n  #{spam.filename}\n#{spam.error_message}\n"
        else
          @report += spam.summary
        end
        @report += "Quarantined as:\n#{@directory}/#{spam.filename}\n\n"
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
    m_id = (DateTime.now).strftime("%y%m%d%H%M%S")
    header = "From: #{@from_name} <#{@from_address}>\n"
    header += "To: #{@to_name} <#{@to_address}>\n"
    header += "Subject: Spam Report For #{@report_date}\n"
    header += "Message-ID: <spamreport-#{m_id}@#{@server_name}>\n\n"
  end

end

class Spam
  attr_accessor :filename, :from, :to, :subject, :sa_status, :error_message, :maildate
  attr_reader :re_from, :re_to, :re_subject, :re_sa_status, :re_date

  def initialize
    @re_from = /^From: .*/
    @re_to = /^To: /
    @re_subject = /^Subject: .*/
    @re_date = /^Date: .*/
    @re_sa_status = /^X-Spam-Status: .*/
    @from = "From: ?\n"
    @to = "To: ?\n"
    @subject = "Subject: ?\n"
    @sa_status = "Status: ?\n"
    @maildate = "Date: \n"
    @count = 0
    @error_message = nil
  end

  def feed(line)

### check every line for encoding to prevent "invalid byte sequence in UTF-8" errors
    detection = CharlockHolmes::EncodingDetector.detect(content)
    line = CharlockHolmes::Converter.convert line, detection[:encoding], 'UTF-8'

    case line
    when re_from
      @from = Mail::Encodings.unquote_and_convert_to( line, 'utf-8' )
    when re_to
      @to =  Mail::Encodings.unquote_and_convert_to( line, 'utf-8' )
    when re_subject
      @subject =  Mail::Encodings.unquote_and_convert_to( line, 'utf-8' )
    when re_date
      @maildate = line
    when re_sa_status
      @sa_status = line
    else
      return
    end
    @count += 1
  end
  
  # count of entries in resport text
  def full?
    @count == 5
  end

  def has_error?
    @error_message != nil
  end
  
  # returning mail_date if necessary
  def mail_date
    @maildate
  end
  
  # returning mail_sender if necessary
  def mail_sender
    @from
  end
  
  def summary
    @from + @to + @subject + @sa_status + @maildate
  end
end

my_sorter = Sorter.new
my_sorter.run
