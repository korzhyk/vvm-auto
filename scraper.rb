require 'scraperwiki'
require 'mechanize'
require 'nokogiri'
require 'reverse_markdown'
require 'zlib'

$agent = Mechanize.new
$site_url = "https://vvm-auto.ru"

def parse_pages(url, data={})
  p "[debug] Parsing #{data[:type]} from #{url}"
  page = $agent.get(url)
  next_page_link = page.search('span.icon-next').length ? page.search('span.icon-next').first.parent['href'] : nil
  parse_page(data)
  if next_page_link
    parse_pages($agent.resolve(next_page_link), data) 
  end
end

def parse_page(data={})
  page = $agent.page
  posts = page.search('#content [itemprop="blogPost"]')
  posts.each do |post|
    link_to_post = post.search('a').first
    url = $agent.resolve(link_to_post['href'])
    id = /\/(\d+)-/.match(url.to_s)[1].to_i

    begin
      article = ScraperWiki.select('* FROM data WHERE id = ? LIMIT 1', [id]).first
      next unless article.nil?
    rescue => e
      p "Database error #{e.to_s}"
    end

    title = post.search('a').first.child.content.strip
    annotation_text = post.search('p').first.nil? ? nil : post.search('p').first.child.content
    annotation_image = post.search('[itemprop="thumbnailUrl"]').first.nil? ? nil : post.search('[itemprop="thumbnailUrl"]').attribute('src').value

    data.merge!({
      id: id,
      title: title,
      annotation_text: ReverseMarkdown.convert(annotation_text),
      annotation_image: "#{$site_url}#{annotation_image}",
      url: url.to_s
    })
    
    $agent.get(url)
    parse_article(data)
    ScraperWiki.save_sqlite([:id], data)
    
    p "[debug] Article with id = #{data[:id]} was parsed, full link: #{url}"
    sleep 5
  end
end

def parse_article(data={})
  page = $agent.page
  category = page.search('[itemprop="genre"]').first
  category = category.text unless category.nil?
  content = page.search('[itemprop="articleBody"]').first
  content.search('div.custom').each { |d| d.remove }
  content.search('script').each { |d| d.remove }
  content.search('img').each do |i|
    i['src'] = $agent.resolve(i['src']).to_s
    scraped = scrape_image(i['src'])
    i.remove unless scraped
  end

  format_content(content)

  html = content.inner_html
  md = ReverseMarkdown.convert(html)
  
  data.merge!({
    category: category,
    html: html,
    md: md
  })
end

def format_content(node)
  
  allowed = %w(alt title href src)
  node.attribute_nodes.each { |a| a.remove unless allowed.include?(a.name) }
  
  unless node.children.empty?
    node.children.each { |c| format_content(c) }  
  end

  if node.text? && node.blank?
    node.remove
  end
  
  block_elements = %w(div p)
  table_elements = %W(td th)
  
  if node.element? && block_elements.include?(node.name) && node.parent && table_elements.include?(node.parent.name)
    node.swap node.children
  end
  
  if node.element? && node.name == 'table'
    if !node.children.empty? && node.children.first.name != 'thead'
      first_tr = node.search('tr').first
      first_tr.children.each { |c| c.name = 'th'} if first_tr
    end
  end
  
  nbsp = Nokogiri::HTML("&nbsp;").text
  if node.text? && node.text == nbsp
    node.remove
  end
  
  if node.name != 'img' && !node['src'] && !node.text? && node.children.empty?
    node.remove
  end
end

def scrape_image(url)
  return nil unless url
  begin
    image = $agent.get_file(url)
    image = Zlib::Deflate.deflate(image)
    ScraperWiki.save_sqlite([:url], { url: url.to_s, blob: image }, 'images').first
  rescue => e
    p "[debug] Image error #{url} - #{e.to_s}"
    nil
  end
end

$agent.get($site_url).search('[role="navigation"] a').each do |link|
  parse_pages($site_url + link['href'], type: link.text)
end
