test: install
	cd test && python test_cparser_compat.py

install:
	python setup.py build
	pip install . -U

annotate:
	cython -a pyteomics/*.pyx
