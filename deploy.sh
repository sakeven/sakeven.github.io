#!/bin/bash

msg="$@"

git add .
git commit -m "$msg"
git push origin code

hugo
cd public
git add .
git commit -m "$msg"
git push origin master
