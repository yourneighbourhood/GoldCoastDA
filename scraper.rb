require 'scraperwiki'
require 'mechanize'

case ENV['MORPH_PERIOD']
when 'thismonth'
  period = 'thismonth'
when 'lastmonth'
  period = 'lastmonth'
else
  period = 'thisweek'
end
puts "Getting '" + period + "' data, changable via MORPH_PERIOD environment";

starting_url = 'http://pdonline.goldcoast.qld.gov.au/masterview/modules/ApplicationMaster/default.aspx?page=found&1=' +period+ '&4a=BLD%27,%27MCU%27,%27OPW%27,%27ROL&6=F'
comment_url = 'mailto:gcccmail@goldcoast.qld.gov.au'

def clean_whitespace(a)
  a.gsub("\r", ' ').gsub("\n", ' ').squeeze(" ").strip
end

# Extending Mechanize Form to support doPostBack
# http://scraperblog.blogspot.com.au/2012/10/asp-forms-with-dopostback-using-ruby.html
class Mechanize::Form
  def postback target, argument
    self['__EVENTTARGET'], self['__EVENTARGUMENT'] = target, argument
    submit
  end
end

def scrape_table(doc, comment_url)
  doc.search('table tbody tr').each do |tr|
    # Columns in table
    # Show  Number  Submitted  Details
    tds = tr.search('td')
    h = tds.map{|td| td.inner_html}

    record = {
      'council_reference' => clean_whitespace(h[1]),
      'address' => clean_whitespace(tds[3].at('b').inner_text) + ' QLD',
      'description' => CGI::unescapeHTML(clean_whitespace(h[3].split('<br>')[1..-1].join.gsub(/<\/?b>/,''))),
      'info_url' => (doc.uri + tds[0].at('a')['href']).to_s,
      'comment_url' => comment_url,
      'date_scraped' => Date.today.to_s,
      'date_received' => Date.strptime(clean_whitespace(h[2]), '%d/%m/%Y').to_s
    }

    if (ScraperWiki.select("* from data where `council_reference`='#{record['council_reference']}'").empty? rescue true)
      puts "Saving record " + record['council_reference'] + ", " + record['address']
#       puts record
      ScraperWiki.save_sqlite(['council_reference'], record)
    else
      puts "Skipping already saved record " + record['council_reference']
    end
  end
end


agent = Mechanize.new
doc = agent.get(starting_url)

scrape_table(doc, comment_url)

# Is there more than a page?
begin
  totalPages = doc.at('div .rgInfoPart').inner_text.split(' items in ')[1].split(' pages')[0].to_i
rescue
  totalPages = 1
end

# run a loop if there are more than a page
(2..totalPages).each do |i|
  puts "scraping for page " + i.to_s + " of " + totalPages.to_s + " pages"

  nextButton = doc.at('.rgPageNext')
  target, argument = nextButton[:onclick].scan(/'([^']*)'/).flatten
  doc = doc.form.postback target, argument
  scrape_table(doc, comment_url)
  i += i
end
