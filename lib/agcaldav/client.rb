module AGCalDAV
    class Client
        include Icalendar
        attr_accessor :host, :port, :url, :user, :password, :ssl

        def format=( fmt )
            @format = fmt
        end

        def format
            @format ||= Format::Debug.new
        end

        def initialize( data )                                        

            proxy_uri   = URI(data["proxy_uri"])
            @proxy_host = proxy_uri.host 
            @proxy_port = proxy_uri.port.to_i
            @proxy_url  = [ proxy_uri.scheme, '://', proxy_uri.host, ':', proxy_uri.port ].join('') 

            uri = URI(data["uri"])
            @host     = uri.host
            @port     = uri.port.to_i
            @url      = [ uri.scheme, '://', uri.host, ':', uri.port, uri.path ].join('') 
            @user     = data["user"]
            @password = data["password"] 
            @ssl      = uri.scheme == 'https'            
        end
    
        def __create_http
          if @proxy_uri.blank?
            http = Net::HTTP.new(@host, @port)
          else        
            http = Net::HTTP.new(@host, @port, @proxy_host, @proxy_port)
          end
            http.use_ssl = @ssl
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
            #http.set_debug_output $stderr
            http
        end
    
        def report datetime_start, datetime_stop            
            res = nil
            __create_http.start {|http|
                req = Net::HTTP::Report.new(@url, initheader = {'Content-Type'=>'application/xml'} )
                req.basic_auth @user, @password
                req.body = AGCalDAV::Request::ReportVEVENT.new(DateTime.parse(datetime_start).strftime("%Y%m%dT%H%M"), 
                                                             DateTime.parse(datetime_stop).strftime("%Y%m%dT%H%M") ).to_xml
                res = http.request( req )
            }
            format.parse_calendar( res.body )
        end
        
        def get uuid
            res = nil
            __create_http.start {|http|
                req = Net::HTTP::Get.new("#{@url}/#{uuid}.ics")
                req.basic_auth @user, @password
                res = http.request( req )
            }
            raise AuthenticationError if res.code.to_i == 401
            raise APIError if res.code.to_i >= 500
            format.parse_single( res.body )
        end
    
        def delete uuid
            __create_http.start {|http|
                req = Net::HTTP::Delete.new("#{@url}/#{uuid}.ics")
                req.basic_auth @user, @password
                res = http.request( req )
            }
        end
    
        def create event
            event.uid = UUID.generate
            event.dtstamp = DateTime.now.strftime "%Y%m%dT%H%M%SZ"
            event.dtstart = event.dtstart.strftime("%Y%m%dT%H%M%S")
            event.dtend = event.dtend.strftime("%Y%m%dT%H%M%S")
            cal = Calendar.new
            cal.event = event if event.is_a? Event
            c = cal.to_ical
            res = nil
            http = Net::HTTP.new(@host, @port) 
            __create_http.start { |http|
                req = Net::HTTP::Put.new("#{@url}/#{event.uid}.ics")
                req['Content-Type'] = 'text/calendar'
                req.basic_auth @user, @password
                req.body = dings
                res = http.request( req )
            }
            return event.uid, res
        end
    
        def add_alarm tevent, altCal="Calendar"
            # FIXME create icalendar event -> cal.event.new (tevent)  
            dtstart_string = ( Time.parse(tevent.dtstart.to_s) + Time.now.utc_offset.to_i.abs ).strftime "%Y%m%dT%H%M%S"
            dtend_string = ( Time.parse(tevent.dtend.to_s) + Time.now.utc_offset.to_i.abs ).strftime "%Y%m%dT%H%M%S"
            alarmText = <<EOL
BEGIN:VCALENDAR
VERSION:2.0
PRODID:Ruby iCalendar
BEGIN:VEVENT
UID:#{tevent.uid}
SUMMARY:#{tevent.summary}
DESCRIPTION:#{tevent.description}
DTSTART:#{dtstart_string}
DTEND:#{dtend_string}
BEGIN:VALARM
ACTION:DISPLAY
TRIGGER;RELATED=START:-PT5M
DESCRIPTION:Reminder
END:VALARM
BEGIN:VALARM
TRIGGER:-PT5M
ACTION:EMAIL
ATTENDEE:#{tevent.organizer}
SUMMARY:#{tevent.summary}
DESCRIPTION:#{tevent.description}
TRIGGER:-PT5M
END:VALARM
END:VEVENT
END:VCALENDAR
EOL
            p alarmText
            res = nil
            puts "#{@url}/#{tevent.uid}.ics"
            thttp = __create_http.start
            #thttp.set_debug_output $stderr
            req = Net::HTTP::Put.new("#{@url}/#{tevent.uid}.ics", initheader = {'Content-Type'=>'text/calendar'} )
            req.basic_auth @user, @password
            req.body = alarmText
            res = thttp.request( req )
            p res.inspect
    
            return tevent.uid
        end
        
        def update event
            dings = """BEGIN:VCALENDAR
PRODID:Caldav.rb
VERSION:2.0

BEGIN:VTIMEZONE
TZID:/Europe/Vienna
X-LIC-LOCATION:Europe/Vienna
BEGIN:DAYLIGHT
TZOFFSETFROM:+0100
TZOFFSETTO:+0200
TZNAME:CEST
DTSTART:19700329T020000
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3
END:DAYLIGHT
BEGIN:STANDARD
TZOFFSETFROM:+0200
TZOFFSETTO:+0100
TZNAME:CET
DTSTART:19701025T030000
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10
END:STANDARD
END:VTIMEZONE

BEGIN:VEVENT
CREATED:#{event.created}
UID:#{event.uid}
SUMMARY:#{event.summary}
DTSTART;TZID=Europe/Vienna:#{event.dtstart}
DTEND;TZID=Europe/Vienna:#{event.dtend.rfc3339}
END:VEVENT
END:VCALENDAR"""
    
            res = nil
            __create_http.start {|http|
                req = Net::HTTP::Put.new("#{@url}/#{event.uid}.ics", initheader = {'Content-Type'=>'text/calendar'} )
                req.basic_auth @user, @password
                req.body = dings
                res = http.request( req )
            }
            return event.uid
        end
    
        def todo 
            res = nil
            __create_http.start {|http|
                req = Net::HTTP::Report.new(@url, initheader = {'Content-Type'=>'application/xml'} )
                req.basic_auth @user, @password
                req.body = AGCalDAV::Request::ReportVTODO.new.to_xml
                res = http.request( req )
            }
            # FIXME: process HTTP code
            format.parse_todo( res.body )
        end
        
        def filterTimezone( vcal )
            data = ""
            inTZ = false
            vcal.split("\n").each{ |l| 
                inTZ = true if l.index("BEGIN:VTIMEZONE") 
                data << l+"\n" unless inTZ 
                inTZ = false if l.index("END:VTIMEZONE") 
            }
            return data
        end
    end

  class AGCalDAVError < StandardError
  end
  class AuthenticationError < AGCalDAVError; end
  class APIError            < AGCalDAVError; end
end