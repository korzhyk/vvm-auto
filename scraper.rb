require 'scraperwiki'
require 'mechanize'
require 'reverse_markdown'

$agent = Mechanize.new
$site_url = "http://vvm-auto.ru"
$image_scraped = nil


def parse_pages(url, data={})
  return if url.nil?
  p "Parsing #{data[:type]} from #{$site_url}#{url}"
  #agent = Mechanize.new
  page = $agent.get("#{$site_url}#{url}")
  next_page_link = page.search('span.icon-next').length ? page.search('span.icon-next').first.parent : nil
  parse_page(data)
  p next_page_link
  unless next_page_link.nil?
    $agent.get($agent.resolve next_page_link['href'])
    p "Go to next page #{next_page_link['href']}"
    parse_page(type: data[:type]) 
  end
end

def parse_page(data={})
  page = $agent.page
  posts = page.search('#content [itemprop="blogPost"]')
  posts.each do |post|
    link_to_post = post.search('a').first
    url = link_to_post['href']
    id = /\/(\d+)-/.match(url)[1].to_i

    begin
      article = ScraperWiki.select('* FROM data WHERE id = ? LIMIT 1', [id]).first
      next unless article.nil?
    rescue => error
      p "Database error: #{error.to_s}"
    end

    title = post.search('a').first.child.content.strip
    annotation_text = post.search('p').first.nil? ? nil : post.search('p').first.child.content
    annotation_image = post.search('[itemprop="thumbnailUrl"]').first.nil? ? nil : post.search('[itemprop="thumbnailUrl"]').attribute('src').value

    if annotation_image && !$image_scraped
      $image_scraped = scrape_image("#{$site_url}#{annotation_image}")
      p $image_scraped
    end

    data.merge!({
      id: id,
      title: title,
      annotation_text: ReverseMarkdown.convert(annotation_text),
      annotation_image: "#{$site_url}#{annotation_image}",
      url: $agent.resolve(url).to_s
    })
    $agent.get($agent.resolve url)
    parse_article(data)
    ScraperWiki.save_sqlite([:id], data)
    #p "#{data[:id]} - #{data[:title]} - #{data[:url]}"
    sleep 1
  end
end

def parse_article(data={})
  #agent = Mechanize.new
  page = $agent.page #$agent.get(url)

  content = page.search('[itemprop="articleBody"]').first
  content.search('div.custom').each { |d| d.remove }
  content.search('*').each do |c|
    c.remove if c.blank?
    c.attributes.clear
  end
  content.search('img').each do |i|
    i.attribute('src').value = $site_url + i.attribute('src').value
  end

  data.merge!({
    content: ReverseMarkdown.convert(content.to_s)
  })
end

def scrape_image(url)
  return nil unless url
  image = $agent.get_file(url)
  p image
  image ? "sqlite://data.db/images/1" : nil
end


{
  experience: "opyt-ekspluatatsii",
  articles: "publikatsii",
  tests: "test-obzor"
}.each do |type, url|
  p "[debug] Load #{type} from #{url}"
  parse_pages("/" << url, type: type.to_s)
end
