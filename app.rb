require 'roda'
require 'httpclient'
require 'nokogiri'

class App < Roda

  plugin :render, :engine=>'haml'

  def img(x)
    doc = <<-HERE
      <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DT
      <html xmlns="http://www.w3.org/1999/xhtml">
      <head><meta charset="UTF-8" /></head><body>#{x}</body></html>
    HERE
    Nokogiri::HTML(doc).at_css('img')
  end
  
  # keep <script> contents untouched
  def html(x)
    doc = <<-HERE
      <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
      <html xmlns="http://www.w3.org/1999/xhtml">
      <head><meta charset="UTF-8" /></head><body>#{x}</body></html>
    HERE
    Nokogiri::HTML(doc).css('body').children
  end

  hc = HTTPClient.new
  hc.ssl_config.verify_mode =  OpenSSL::SSL::VERIFY_NONE
  hc.set_cookie_store('cookies.dat')
  hc.transparent_gzip_decompression = true
  hc.agent_name = 'Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:47.0) Gecko/20100101 Firefox/47.0'
  
  route do |r|

    # form is submitted as POST
    r.post do
      url = r['url']
      if url
        url =~ /^\s*((https?):\/\/)?(.+?)$/
        proto = $2 ? $2 : 'https'
        remain = $3.gsub(/^\/+/,'')
        url = "/#{r['level']}/#{proto}/#{remain}"
        r.redirect url
      end
    end

    r.root do
      view 'index'
    end
    
    r.get 'robots.txt' do
      'disallow: /'
    end
    
    r.on 'public' do
      r.run Rack::File.new('./public')
    end
    
    r.get 'favicon.ico' do
      File.open('./public/favicon.ico').read
    end
    
    r.on String, String do |level, proto|
      
      @level = level
      @proto = proto

      ary = r.remaining_path.split('/')
      
      @domain = ary[1]
      
      if @domain =~ /generaliceska.cz/
        r.redirect 'https://generaliceska.cz'
      end

      @path = ary[2..-1].join('/')
      @path << '/' if r.env['PATH_INFO'][-1] == '/'  # trailing slash is necessary sometimes, repeat it
      @path = '' if @path=='/'
      
      url = "#{@proto}://#{@domain}/#{@path}"

      $log.debug "URL: #{url}"
            
      headers = {}
      if r.env['PATH_INFO'] == '/rss'
        res = hc.get(url, nil, headers)
      else
        res = hc.get(url, r.env['QUERY_STRING'], headers)
      end
      
      # redirect? "proxy" it...
      if (300..302).include?(res.status)
        res.header['location'].first =~ /^[\s"']*((https?):\/\/)?([^\/]+)/
        proto = $2 ? $2 : @proto
        url = "/#{@level}/#{proto}/#{$3}"
        r.redirect url
      end
      
      # good, we've got some contents...
      body = res.body.clone
      body.gsub!(/Borgis,? a\.s\./,'Vykradeno a.s.')
      body.gsub!(/Seznam\.cz,? a\.s\./,'Vytunelováno a.s.')

      # we process also RSS
      is_xml = false
      noko = if res.header['Content-Type'][0] =~ /text\/xml/ #rss
        is_xml = true
        Nokogiri::XML.parse(body)
      elsif res.header['Content-Type'][0] =~ /text\/html/
        Nokogiri::HTML.parse(body)
      else
        nil
      end
        
      if noko

        if noko.css('head').length>0  # is html
          
          noko.css('head/meta[property="og:description"]').remove
          noko.css('head/meta[property="og:type"]').remove
          noko.css('head/meta[property="og:title"]').remove
          noko.css('head/meta[property="og:url"]').remove
          noko.css('head/meta[property="og:image"]').remove
          noko.css('head/meta[property="og:image:width"]').remove
          noko.css('head/meta[property="og:image:height"]').remove
          noko.css('head/meta[property="og:site_name"]').remove
          noko.css('head').first << html("<meta property='og:url' content='https://sracky.1984.cz'/>")
          noko.css('head').first << html("<meta property='og:description' content='Sračky'/>")
          noko.css('head').first << html("<meta property='og:type' content='article'/>")
          noko.css('head').first << html("<meta property='og:title' content='Sračky'/>")
          noko.css('head').first << html("<meta property='og:image' content='https://sracky.1984.cz/public/og2.jpg'/>")
          noko.css('head').first << html("<meta property='og:image:width' content='617'/>")
          noko.css('head').first << html("<meta property='og:image:height' content='862'/>")
          noko.css('head').first << html("<meta property='og:site_name' content='Sračky'/>")

          if tit = noko.css('title').first
            tit.content = 'Sračky'
          end

          if inp = noko.at_css('input[placeholder="Hledat..."]')
            inp['placeholder'] = 'Sračky...'
          end

          # novinky.cz logo replace
          if a = noko.at_css("a.ogm-header-big-logo")
            a.children.remove
            a << img('<img src="/public/novinky-logo.gif"/>')
          end
          
          noko.css('base').remove
          noko.css('script').remove
          noko.css('noscript').each do |x|
            x.replace(x.children)  # show images from noscript
          end

        end

        # process text
        noko.traverse do |node|
          if node.name == 'text'
            rep = node.content.to_s
            
            next if rep=~/^[Dd]nes \d?\d:\d\d/ || 
                    rep=~/^\s*\d\d:\d\d\s*$/ || 
                    rep=~/Vykradeno|Vytunelo/ || 
                    rep=~/celý článek|čas čtení.*?minut|Vytisknout|Diskuse|Váš komentář|Komentáře|Obsah vydání|Rubriky|nejnovější|oblíbené|Nejsdílenější dnes|Nejčtenější|Týden|Měsíc|Rok|Vše/m ||
                    rep=~/Aktualizováno/ || 
                    rep=~/ROZHOVOR/ || 
                    rep=~/Copyright/ || 
                    rep=~/^\s*\d+(\.\d+)?\s*%$/ || 
                    rep=~/^\d+(\.\d+)?$/

            squared = lambda { rand(20)==0 && @level!='sick' ? '²' : '' } # sracky²
            nineteen = lambda { rand(7)==0 ? '-19' : '' }

            sracka1 = lambda do |typ|
              a = case @level
                when 'lite'
                  %W( sračky )
                when 'sick'
                  %W( covid mrtví zemřeli tragédie krach smrt globálně očkovaní neočkovaní šílení dezinformace zabití ohrožení kolaps brutální poškození likvidace rasismus EU Rusko konec násilí zabíjejí krize nebezpečně apokalypsa neuvěřitelně covidioti idioti koronavirus drastický zuřivě absolutně útočící nejistota šíření vrazi vražedně nenávist )
                else
                  %W( sračky hovna zvratky píčoviny kokotiny demence covid )
              end
              s = a[rand(a.length)]
              case typ
                when :upcase
                  s.upcase << nineteen.call << squared.call
                when :camelize
                  s[0].upcase << s[1..-1] << squared.call
                when :normal
                  s
              end
            end

            sracka4 = lambda do |n, typ|
              a = case n.to_i
                when 1
                  case @level
                    when 'lite'
                      %W( sračka )
                    when 'sick'
                      %W( mrtvý zemřelý tragédie krach smrt očkovaní zabitý covidiot koronavirus šílenec )
                    else
                      %W( sračka hovno zvratek píčovina kokotina covid )
                  end
                when 2..4
                  case @level
                    when 'lite'
                      %W( sračky )
                    when 'sick'
                      %W( mrtví zemřelí zabití ohrožení covidioti )
                    else
                      %W( sračky hovna zvratky píčoviny kokotiny covidy šílenci )
                  end
                else
                  case @level
                    when 'lite'
                      %W( sraček )
                    when 'sick'
                      %W( mrtvých zemřelých očkovaných zabití ohrožení apokalyps covidiotů koronavirů podvodů šílenců )
                    else
                      %W( sraček hoven zvratků píčovin kokotin covidů )
                  end
              end
              s = a[rand(a.length)]
              case typ
                when :upcase
                  s.upcase << nineteen.call << squared.call
                when :camelize
                  s[0].upcase << s[1..-1] << squared.call 
                when :normal
                  s
              end
            end

            select_sracka1 = lambda do |a,b,c|
              if a
                sracka1.call(:camelize)
              elsif b
                sracka1.call(:normal)
              elsif c
                sracka1.call(:upcase)
              end
            end

            # as if it was just one word...
            rep.gsub!(/idnes\.\w+|novinky\.\w+|seznam zpr.vy/i,'Xxx')

            rep.gsub!(/([ \s]+[\d,]+[ \s]*)?(([A-ZÁČĎĚÉÍŇÓŘŠŤÚǓÝŽÜÖÄËŸ][a-záčďéěíňóřšťúůýžüöäÿ]+)|([a-záčďéěíňóřšťúůýžüöäÿ]+)|([A-ZÁČĎĚÉÍŇÓŘŠŤÚǓÝŽÜÖÄËŸ]+))/) do

              if $1 # there is a number 
                if (1900..2055).member?($1.to_i)
                  # the number is in interval => nominativ (as normal)
                  $1 << select_sracka1.call($3, $4, $5)
                else
                  # otherwise add sracka in accusative after the number
                  if $3
                    $1 << sracka4.call($1, :camelize)
                  elsif $4
                    $1 << sracka4.call($1, :normal)
                  elsif $5
                    $1 << sracka4.call($1, :upcase)
                  end
                end
              else
                select_sracka1.call($3, $4, $5)
              end
            end
            
            node.content = rep
          end

        end
        
        # process links...
        # https?://www.zbozi.cz/magazin/c/black-friday/ => /@level/proto/www.zbozi.cz/magazin/c/black-friday
        # //www.facebook.com/Novinky.cz/ => /@level/@proto/www.facebook.com/Novinky.cz/
        # /domaci => /@level/@proto/@domain/domaci 
        begin
          noko.xpath("//*[self::a or self::iframe]").each do |node|
            %w[ href src ].each do |attr|
              next unless node[attr]
              
              x = node[attr].clone
              
              if x =~ /^(https?):\/\/(.+?)$/
                node[attr] = "/#{@level}/#{$1}/#{$2}"
              elsif x =~ /^\/\/(.+?)$/
                node[attr] = "/#{@level}/#{@proto}/#{$1}"
              elsif x =~ /^\/(.+?)$/
                node[attr] = "/#{@level}/#{@proto}/#{@domain}/#{$1}"
              end
  
              if node.name=='iframe'
                if node[attr] =~ /\?/
                  node[attr] = node[attr]+'&in_iframe=1'
                else
                  node[attr] = node[attr]+'?in_iframe=1'
                end
              end

            end
          end
        rescue Exception
        end

        # process images/scripts/links (load from original)
        # /foo.css => proto://domain/foo.css
        # /foo.jpg => proto://domain/foo.jpg
        begin
          noko.xpath("//*[self::link or self::img or self::script or self::source]").each do |node|

            node.remove_attribute('srcset')
            
            %w[ href src ].each do |attr|

              next unless node[attr]
              next if node[attr] =~ /^\/public\/(favicon\.ico|novinky-logo\.gif)/ # already replaced

              if node[attr] !~ /^(https?:\/\/|\/\/)/
                node[attr] = "#{@proto}://#{@domain}#{node[attr]}"
              end

            end

          end
        rescue Exception
        end

        # add srackomat link to the top unless in iframe
        unless r['in_iframe']
          if noko.css('head').length>0
            noko.css('head').first.prepend_child html("<link rel='stylesheet' type='text/css' href='/public/srackomat-logo.css?#{File.open('public/srackomat-logo.css').mtime.to_i}'/>")
            noko.css('body').first.prepend_child html("<div id='srackomat-logo'><a href='/'>Sračkomat</a></div>")
          end
        end

        # produce rss or html?
        body = if is_xml
          noko.to_xml
        else
          noko.to_html
        end
          
      end # of noko.traverse

      # repeat original content-type
      response.status = res.status
      ['Content-Type'].each do |h|
        response[h] = res.header[h][0]
      end

      body
    end

    # otherwise...
    r.redirect '/'

  end # of route

end

