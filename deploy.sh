#!/bin/bash

msg="$@"

git add .
git commit -m "$msg"
git push origin code


mv public/.git .gittmp
rm -rf public
hugo
mv .gittmp public/.git

cd public
git add .
git commit -m "$msg"
git push origin master
