maintainer       "Eric G. Wolfe"
maintainer_email "eric.wolfe@gmail.com"
license          "Apache 2.0"
description      "Installs/Configures gitlab"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
name             "gitlab"
version          "6.2.0"
%w[ build-essential zlib readline ncurses git openssh redisio xml
    python ruby_build sudo certificate nginx database mysql
    postgresql yum apt ].each do |cb_depend|
  depends cb_depend
end

%w[ redhat centos scientific amazon debian ubuntu ].each do |os|
  supports os
end
