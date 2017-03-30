#!/bin/bash
#
# Build the OpTiMSoC documentation for the web page
#

OPTIMSOC_REPO_URL=${1:-https://github.com/optimsoc/sources.git}

# switch to script directory
TOPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$TOPDIR"

SPHINXBUILD=$TOPDIR/.venv/bin/sphinx-build

function build_docs {
  SRCDIR=$1
  OUTDIR=$2
  VERSION=$3
  CSET=$4

  # target directory
  mkdir -p "$OUTDIR"

  # object directory (temporary build files)
  OBJDIR=$TOPDIR/buildtmp/objdir
  rm -rf $OBJDIR
  mkdir -p $OBJDIR

  # Switch to requested version
  cd "$SRCDIR"
  git checkout "$CSET"

  # User guide: HTML
  mkdir -p $OBJDIR/user_guide/{tex,xml,html}
  cp $SRCDIR/doc/user_guide/* $OBJDIR/user_guide/tex
  cp -r $SRCDIR/doc/user_guide/img $OBJDIR/user_guide/tex
  cp $TOPDIR/docbuild/user_guide-html.tex $OBJDIR/user_guide/tex

  latexml --dest=$OBJDIR/user_guide/xml/user_guide.xml \
    $OBJDIR/user_guide/tex/user_guide-html.tex
  latexmlpost --navigationtoc=context --splitat=chapter --splitnaming=label \
    --sourcedirectory=$OBJDIR/user_guide/tex \
    --stylesheet=$TOPDIR/docbuild/latexml-optimsoc.xsl --format=html \
    --dest=$OBJDIR/user_guide/html/user_guide.html \
    --xsltparameter=OPTIMSOC_TITLE:"User Guide" \
    --xsltparameter=OPTIMSOC_DOCID:"user-guide" \
    --xsltparameter=OPTIMSOC_VERSION:"$VERSION" \
    --xsltparameter=OPTIMSOC_SOURCES_CSET:"$CSET" \
    $OBJDIR/user_guide/xml/user_guide.xml

  mkdir -p $OUTDIR/user-guide
  cp $OBJDIR/user_guide/html/*.html $OUTDIR/user-guide
  cp -r $OBJDIR/user_guide/html/img $OUTDIR/user-guide
  test -d $OBJDIR/user_guide/html/mi && cp -r $OBJDIR/user-guide/html/mi $OUTDIR/user_guide

  # User guide: PDF
  mkdir -p $OBJDIR/user_guide/pdf
  (
    cd $SRCDIR/doc/user_guide
    pdflatex -output-directory $OBJDIR/user_guide/pdf user_guide.tex || exit
    pdflatex -output-directory $OBJDIR/user_guide/pdf user_guide.tex
  )
  cp $OBJDIR/user_guide/pdf/user_guide.pdf $OUTDIR/user-guide.pdf

  # Reference Manual
  VENV=$TOPDIR/.venv make -C $SRCDIR/doc/api
  if [ -e $SRCDIR/doc/refman/index.rst ]; then
    $SPHINXBUILD -b html -D html_theme=sphinxtheme \
      -D html_theme_path=$TOPDIR/docbuild \
      -D version=$VERSION \
      $SRCDIR/doc $OUTDIR/
  fi
}

# Prepare Sphinx
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install --upgrade -r sphinx_requirements.txt

# get sources
git clone $OPTIMSOC_REPO_URL $TOPDIR/buildtmp/optimsoc

# current master and all release versions (all annotated tags starting with 'v')
# |git tag -l| is not able to select only annotated tags?!
RELEASE_TAGS=$(cd $TOPDIR/buildtmp/optimsoc;
  git for-each-ref refs/tags/v\* --format '%(objecttype) %(refname:short)' |
    awk '$1 == "tag" {print $2}' |
    sort -Vr)

CSETS="master $RELEASE_TAGS"
CURRENT_RELEASE_VERSION=$(echo $RELEASE_TAGS | cut -d' ' -f1 | tr -d 'v')

for CSET in $CSETS; do
  # XXX: Switch to tools/get-version.sh inside the source tree once all
  # "new enough" versions have it (starting with 2016.1)
  if [ "$CSET" == "master" ]; then
    OPTIMSOC_VERSION=master
  else
    OPTIMSOC_VERSION=$(echo $CSET | tr -d 'v')
  fi
  OPTIMSOC_VERSIONS="$OPTIMSOC_VERSIONS $OPTIMSOC_VERSION"

  # only rebuild if required, i.e. if commit id changed
  CSET_HASH=$(cd $TOPDIR/buildtmp/optimsoc; git rev-parse $CSET)
  if [ -f $TOPDIR/docs/$OPTIMSOC_VERSION/commit_id ] &&
     [ `cat $TOPDIR/docs/$OPTIMSOC_VERSION/commit_id` == "$CSET_HASH" ]; then
    echo "Nothing to do for version $OPTIMSOC_VERSION ($CSET_HASH)"
    continue
  fi

  build_docs $TOPDIR/buildtmp/optimsoc $TOPDIR/docs/$OPTIMSOC_VERSION $OPTIMSOC_VERSION $CSET

  # remember commit ID of this build
  echo $CSET_HASH > $TOPDIR/docs/$OPTIMSOC_VERSION/commit_id
done

# generate data file: list of versions for use in Liquid templates in Jekyll
echo '{% assign doc_version_current_dev = "master" %}' > $TOPDIR/_includes/doc_versions.txt
echo "{% assign doc_version_current_release = '$CURRENT_RELEASE_VERSION' %}" >> $TOPDIR/_includes/doc_versions.txt
# split is used because assigning arrays is not possible in Liquid
echo "{% assign doc_versions = '$OPTIMSOC_VERSIONS'  | split: ' ' %}" >> $TOPDIR/_includes/doc_versions.txt

rm -rf $TOPDIR/buildtmp
