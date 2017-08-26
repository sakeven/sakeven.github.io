#!/bin/bash

msg="$@"

git add .
git commit -m "$msg"
git push origin code


rm -rf public
hugo
cd public
git add .
git commit -m "$msg"
git push origin master
