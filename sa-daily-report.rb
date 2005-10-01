#!/usr/bin/ruby -w

require 'zlib'
require 'date'
require 'net/smtp'

class Sorter
    
    def initialize
        @directory = "/var/amavis/quarantine"
        @dateline = (Date.today - 1).strftime("%Y%m%d")
        @report_date = (Date.today - 1).strftime("%d/%m/%y")
        @file_patt = "spam-*-#{@dateline}-*.gz"
        @spams = Array.new
        @report = ""
        @to_name = "Administrator"
        @to_address = "administrator@primur.com"
        @server = "psrmx.primur.com"
    end

    def run
        scan_spam
        create_report
        mail_report
        #print @report
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
            Net::SMTP.start(@server, 25) { |smtp|
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
