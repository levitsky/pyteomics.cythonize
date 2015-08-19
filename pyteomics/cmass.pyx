import re

cimport cython
from cpython.ref cimport PyObject
from cpython.dict cimport PyDict_GetItem, PyDict_SetItem, PyDict_Next, PyDict_Keys, PyDict_Update
from cpython.int cimport PyInt_AsLong, PyInt_Check, PyInt_FromLong
from cpython.string cimport PyString_Format
from cpython.tuple cimport PyTuple_GetItem, PyTuple_GET_ITEM
from cpython.list cimport PyList_GET_ITEM
from cpython.float cimport PyFloat_AsDouble
from cpython.sequence cimport PySequence_GetItem
from cpython.exc cimport PyErr_Occurred

from pyteomics.auxiliary import PyteomicsError, _nist_mass
from pyteomics.mass import std_aa_mass as _std_aa_mass, std_ion_comp as _std_ion_comp, std_aa_comp as _std_aa_comp


import cparser
from cparser import parse, amino_acid_composition, _split_label
cimport cparser
from cparser cimport parse, amino_acid_composition, _split_label

cdef:
    dict nist_mass = _nist_mass
    dict std_aa_mass = _std_aa_mass
    dict std_ion_comp = {k: CComposition(v) for k, v in _std_ion_comp.items()}
    dict std_aa_comp = {k: CComposition(v) for k, v in _std_aa_comp.items()}


cdef inline double get_mass(dict mass_data, object key):
    cdef:
        PyObject* interm
        double mass

    interim = PyDict_GetItem(mass_data, key)
    if interim == NULL:
        raise KeyError(key)
    interim = PyDict_GetItem(<dict>interim, 0)
    if interim == NULL:
        raise KeyError(0)
    mass = PyFloat_AsDouble(<object>PyTuple_GetItem(<tuple>interim, 0))
    return mass


cpdef double fast_mass(str sequence, str ion_type=None, int charge=0,
                       dict mass_data=nist_mass, dict aa_mass=std_aa_mass,
                       dict ion_comp=std_ion_comp):
    cdef:
        CComposition icomp
        double mass = 0
        int i, num
        Py_ssize_t pos
        str a
        PyObject* pkey
        PyObject* pvalue

    for i in range(len(sequence)):
        a = PySequence_GetItem(sequence, i)
        pvalue = PyDict_GetItem(aa_mass, a)
        if pvalue == NULL:
            raise PyteomicsError('No mass data for residue: ' + a)
        mass += PyFloat_AsDouble(<object>pvalue)
    pvalue = PyErr_Occurred()
    if pvalue != NULL:
        raise (<object>pvalue)("An error occurred in cmass.fast_mass")
    mass += get_mass(mass_data, 'H') * 2 + get_mass(mass_data, 'O')

    if ion_type:
        try:
            icomp = ion_comp[ion_type]
        except KeyError:
            raise PyteomicsError('Unknown ion type: {}'.format(ion_type))
        pos = 0
        while(PyDict_Next(icomp, &pos, &pkey, &pvalue)):
            mass += get_mass(mass_data, <object>pkey) * PyFloat_AsDouble(<object>pvalue)
        pvalue = PyErr_Occurred()
        if pvalue != NULL:
            raise (<object>pvalue)("An error occurred in cmass.fast_mass")

    if charge:
        mass = (mass + get_mass(mass_data, 'H+') * charge) / charge

    return mass


cpdef double fast_mass2(str sequence, str ion_type=None, int charge=0,
                        dict mass_data=nist_mass, dict aa_mass=std_aa_mass,
                        dict ion_comp=std_ion_comp):
    """Calculate monoisotopic mass of an ion using the fast
    algorithm. *modX* notation is fully supported.

    Parameters
    ----------
    sequence : str
        A polypeptide sequence string.
    ion_type : str, optional
        If specified, then the polypeptide is considered to be
        in a form of corresponding ion. Do not forget to
        specify the charge state!
    charge : int, optional
        If not 0 then m/z is calculated: the mass is increased
        by the corresponding number of proton masses and divided
        by z.
    mass_data : dict, optional
        A dict with the masses of chemical elements (the default
        value is :py:data:`nist_mass`).
    aa_mass : dict, optional
        A dict with the monoisotopic mass of amino acid residues
        (default is std_aa_mass);
    ion_comp : dict, optional
        A dict with the relative elemental compositions of peptide ion
        fragments (default is :py:data:`std_ion_comp`).

    Returns
    -------
    mass : float
        Monoisotopic mass or m/z of a peptide molecule/ion.
    """
    cdef:
        dict comp
        str aa, mod, X, element
        int num
        double mass, interim
        tuple temp
        CComposition icomp
        Py_ssize_t pos
        PyObject* pkey
        PyObject* pvalue
        PyObject* ptemp

    ptemp = PyDict_GetItem(aa_mass, 'H-')
    if ptemp == NULL:
        PyDict_SetItem(aa_mass, 'H-', get_mass(mass_data, "H"))
    ptemp = PyDict_GetItem(aa_mass, '-OH')
    if ptemp == NULL:
        PyDict_SetItem(aa_mass, '-OH', get_mass(mass_data, "H") + get_mass(mass_data, "O"))

    try:
        comp = amino_acid_composition(sequence,
                show_unmodified_termini=1,
                allow_unknown_modifications=1,
                labels=list(aa_mass))
    except PyteomicsError:
        raise PyteomicsError('Mass not specified for label(s): {}'.format(
            ', '.join(set(parse(sequence)).difference(aa_mass))))

    mass = 0.
    pos = 0
    while(PyDict_Next(comp, &pos, &pkey, &pvalue)):
        aa = <str>pkey
        num = <int>pvalue
        if aa in aa_mass:
            ptemp = PyDict_GetItem(aa_mass, aa)
            mass += PyFloat_AsDouble(<object>ptemp) * num
        else:
            temp = _split_label(aa)
            mod = <str>PyTuple_GET_ITEM(temp, 0)
            X = <str>PyTuple_GET_ITEM(temp, 1)
            ptemp = PyDict_GetItem(aa_mass, mod)
            if ptemp is NULL:
                raise (<object>ptemp)("An error occurred in cmass.fast_mass: %s not found in aa_mass" % mod)
            interim = PyFloat_AsDouble(<object>ptemp)
            ptemp = PyDict_GetItem(aa_mass, X)
            if ptemp is NULL:
                raise (<object>ptemp)("An error occurred in cmass.fast_mass: %s not found in aa_mass" % X)
            interim += PyFloat_AsDouble(<object>ptemp)
            mass += interim * num

    if ion_type:
        try:
            icomp = ion_comp[ion_type]
        except KeyError:
            raise PyteomicsError('Unknown ion type: {}'.format(ion_type))

        pos = 0
        while(PyDict_Next(icomp, &pos, &pkey, &pvalue)):
            mass += get_mass(mass_data, <object>pkey) * PyFloat_AsDouble(<object>pvalue)
        pvalue = PyErr_Occurred()
        if pvalue != NULL:
            raise (<object>pvalue)("An error occurred in cmass.fast_mass")

    if charge:
        mass = (mass + get_mass(mass_data, 'H+') * charge) / charge

    return mass


# Forward Declaration
cdef: 
    str _atom = r'([A-Z][a-z+]*)(?:\[(\d+)\])?([+-]?\d+)?'
    str _formula = r'^({})*$'.format(_atom)
    str _isotope_string = r'^([A-Z][a-z+]*)(?:\[(\d+)\])?$'

    object isotope_pattern = re.compile(_isotope_string)
    object formula_pattern = re.compile(_formula)


@cython.boundscheck(False)
cdef inline str _parse_isotope_string(str label, int* isotope_num):
    cdef:
        # int isotope_num = 0
        int i = 0
        int in_bracket = False
        # str element_name
        str current
        list name_parts = []
        list num_parts = []
        #Isotope result
    for i in range(len(label)):
        current = label[i]
        if in_bracket:
            if current == "]":
                break
            num_parts.append(current)
        elif current == "[":
            in_bracket = True
        else:
            name_parts.append(current)
    element_name = (''.join(name_parts))
    if len(num_parts) > 0:
        isotope_num[0] = (int(''.join(num_parts)))
    else:
        isotope_num[0] = 0
    return element_name


cdef inline str _make_isotope_string(str element_name, int isotope_num):
    """Form a string label for an isotope."""
    cdef:
        tuple parts
    if isotope_num == 0:
        return element_name
    else:
        parts = (element_name, isotope_num)
        return <str>PyString_Format('%s[%d]', parts)


cdef class CComposition(dict):

    '''Represent arbitrary elemental compositions'''
    def __str__(self):   # pragma: no cover
        return 'Composition({})'.format(dict.__repr__(self))

    def __repr__(self):  # pragma: no cover
        return str(self)

    def __iadd__(CComposition self, other):
        cdef:
            str elem
            long cnt
            PyObject *pkey
            PyObject *pvalue
            Py_ssize_t ppos = 0

        while(PyDict_Next(other, &ppos, &pkey, &pvalue)):
            elem = <str>pkey
            cnt = self.getitem(elem)
            self.setitem(elem, cnt + PyInt_AsLong(<object>pvalue))

        self._mass_args = None
        return self


    def __add__(self, other):
        cdef:
            str elem
            long cnt
            CComposition result
            PyObject *pkey
            PyObject *pvalue
            Py_ssize_t ppos = 0
        if not isinstance(self, CComposition):
            other, self = self, other
        result = CComposition(self)
        while(PyDict_Next(other, &ppos, &pkey, &pvalue)):
            elem = <str>pkey
            cnt = result.getitem(elem)
            cnt += PyInt_AsLong(<object>pvalue)
            result.setitem(elem, cnt)

        return result


    def __isub__(self, other):
        cdef:
            str elem
            long cnt
            PyObject *pkey
            PyObject *pvalue
            Py_ssize_t ppos = 0

        while(PyDict_Next(other, &ppos, &pkey, &pvalue)):
            elem = <str>pkey
            cnt = self.getitem(elem)
            self.setitem(elem, cnt - PyInt_AsLong(<object>pvalue))

        self._mass_args = None
        return self

    def __sub__(self, other):
        cdef:
            str elem
            long cnt
            CComposition result
            PyObject *pkey
            PyObject *pvalue
            Py_ssize_t ppos = 0
        if not isinstance(self, CComposition):
            self = CComposition(self)
        result = CComposition(self)
        while(PyDict_Next(other, &ppos, &pkey, &pvalue)):
            elem = <str>pkey
            cnt = result.getitem(elem)
            cnt -= PyInt_AsLong(<object>pvalue)
            result.setitem(elem, cnt)

        return result

    #def __reduce__(self):
    #    return composition_factory, (list(self),), self.__getstate__()

    def __getstate__(self):
        return dict(self)

    def __setstate__(self, d):
        self._from_dict(d)
        self._mass = None
        self._mass_args = None


    def __mul__(self, other):
        cdef:
            CComposition prod = CComposition()
            int rep, v
            str k

        if isinstance(other, CComposition):
            self, other = other, self
        
        if not isinstance(other, int):
            raise PyteomicsError(
                'Cannot multiply Composition by non-integer',
                other)
        rep = other
        for k, v in self.items():
            prod.setitem(k, v * rep)
        return prod


    def __richcmp__(self, other, int code):
        if code == 2:
            if not isinstance(other, dict):
                return False
            self_items = set([i for i in self.items() if i[1]])
            other_items = set([i for i in other.items() if i[1]])
            return self_items == other_items
        else:
            return NotImplemented

    def __neg__(self):
        return self * -1

    # Override the default behavior, if a key is not present
    # do not initialize it to 0.
    def __missing__(self, str key):
        return 0

    def __setitem__(self, str key, int value):
        if value:  # Will not occur on 0 as 0 is falsey AND an integer
            self.setitem(key, value)
        elif key in self:
            del self[key]
        self._mass_args = None

    def copy(self):
        return self.__class__(self)

    cdef inline long getitem(self, str elem):
        cdef:
            PyObject* resobj
            long count
        resobj = PyDict_GetItem(self, elem)
        if (resobj == NULL):
            return 0
        count = PyInt_AsLong(<object>resobj)
        return count

    cdef inline void setitem(self, str elem, long val):
        PyDict_SetItem(self, elem, val)
        self._mass_args = None

    cpdef CComposition clone(self):
        return CComposition(self)

    def update(self, *args, **kwargs):
        dict.update(self, *args, **kwargs)
        self._mass_args = None

    @cython.boundscheck(False)
    cpdef _from_formula(self, str formula, dict mass_data):
        cdef:
            str elem, isotope, number
        if '(' in formula:
            self._from_formula_parens(formula, mass_data)
        elif not formula_pattern.match(formula):
            raise PyteomicsError('Invalid formula: ' + formula)
        else:
            for elem, isotope, number in re.findall(_atom, formula):
                if not elem in mass_data:
                    raise PyteomicsError('Unknown chemical element: ' + elem)
                self[_make_isotope_string(elem, int(isotope) if isotope else 0)
                        ] += int(number) if number else 1

    @cython.boundscheck(True)
    def _from_formula_parens(self, formula, mass_data):
        # Parsing a formula backwards.
        prev_chem_symbol_start = len(formula)
        i = len(formula) - 1

        seek_mode = 0
        parse_stack = ""
        resolve_stack = []
        group_coef = None

        while i >= 0:
            if seek_mode < 1:
                if (formula[i] == ")"):
                    seek_mode += 1
                    if i + 1 == prev_chem_symbol_start:
                        group_coef = 1
                    elif formula[i + 1].isdigit():
                        group_coef = int(formula[i + 1:prev_chem_symbol_start])
                    i -= 1
                    continue
                # Read backwards until a non-number character is met.
                if (formula[i].isdigit() or formula[i] == '-'):
                    i -= 1
                    continue

                else:
                    # If the number of atoms is omitted then it is 1.
                    if i + 1 == prev_chem_symbol_start:
                        num_atoms = 1
                    else:
                        try:
                            num_atoms = int(formula[i + 1:prev_chem_symbol_start])
                        except ValueError:
                            raise PyteomicsError(
                                'Badly-formed number of atoms: %s' % formula)

                    # Read isotope number if specified, else it is undefined (=0).
                    if formula[i] == ']':
                        brace_pos = formula.rfind('[', 0, i)
                        if brace_pos == -1:
                            raise PyteomicsError(
                                'Badly-formed isotope number: %s' % formula)
                        try:
                            isotope_num = int(formula[brace_pos + 1:i])
                        except ValueError:
                            raise PyteomicsError(
                                'Badly-formed isotope number: %s' % formula)
                        i = brace_pos - 1
                    else:
                        isotope_num = 0

                    # Match the element name to the mass_data.
                    element_found = False
                    # Sort the keys from longest to shortest to workaround
                    # the overlapping keys issue
                    for element_name in sorted(mass_data, key=len, reverse=True):
                        if formula.endswith(element_name, 0, i + 1):
                            isotope_string = _make_isotope_string(
                                element_name, isotope_num)
                            self[isotope_string] += num_atoms
                            i -= len(element_name)
                            prev_chem_symbol_start = i + 1
                            element_found = True
                            break

                    if not element_found:
                        raise PyteomicsError(
                            'Unknown chemical element in the formula: %s' % formula)
            else:
                ch = formula[i]
                parse_stack += ch
                i -= 1
                if(ch == "("):
                    seek_mode -= 1
                    if seek_mode == 0:

                        resolve_stack.append(Composition(
                                             # Omit the last character, then reverse the parse
                                             # stack string.
                                             formula=parse_stack[:-1][::-1],
                                             mass_data=mass_data)
                                             * group_coef)
                        prev_chem_symbol_start = i + 1
                        seek_mode = False
                        parse_stack = ""
                elif(formula[i] == ")"):
                    seek_mode += 1
                else:
                    # continue to accumulate tokens
                    pass

        # Unspool the resolve stack, adding together the chunks
        # at this level. __add__ operates immutably, so must manually
        # loop through each chunk.
        for chunk in resolve_stack:
            for elem, cnt in chunk.items():
                self[elem] += cnt

    cpdef _from_dict(self, comp):
        '''
        Directly overwrite this object's keys with the values in
        `comp` without checking their type.
        '''
        PyDict_Update(self, comp)


    cpdef double mass(self, int average=False, charge=None, dict mass_data=nist_mass) except -1:
        cdef int mdid
        mdid = id(mass_data)
        if self._mass_args is not None and average is self._mass_args[0]\
                and charge == self._mass_args[1] and mdid == self._mass_args[2]:
            return self._mass
        else:
            self._mass_args = (average, charge, mdid)
            self._mass = calculate_mass(composition=self, average=average, charge=charge, mass_data=mass_data)
            return self._mass

    def __init__(self, *args, **kwargs):
        """
        A Composition object stores a chemical composition of a
        substance. Basically it is a dict object, in which keys are the names
        of chemical elements and values contain integer numbers of
        corresponding atoms in a substance.

        The main improvement over dict is that Composition objects allow
        addition and subtraction.

        If ``formula`` is not specified, the constructor will look at the first
        positional argument and try to build the object from it. Without
        positional arguments, a Composition will be constructed directly from
        keyword arguments.

        Parameters
        ----------
        formula : str, optional
            A string with a chemical formula. All elements must be present in
            `mass_data`.
        mass_data : dict, optional
            A dict with the masses of chemical elements (the default
            value is :py:data:`nist_mass`). It is used for formulae parsing only.
        """
        dict.__init__(self)
        cdef:
            dict mass_data
            str kwa
            set kw_sources
        mass_data = kwargs.get('mass_data', nist_mass)

        kw_sources = set(
            ('formula',))
        kw_given = kw_sources.intersection(kwargs)
        if len(kw_given) > 1:
            raise PyteomicsError('Only one of {} can be specified!\n\
                Given: {}'.format(', '.join(kw_sources),
                                  ', '.join(kw_given)))

        elif kw_given:
            kwa = kw_given.pop()
            if kwa == "formula":
                self._from_formula(kwargs[kwa], mass_data)
        # can't build from kwargs
        elif args:
            if isinstance(args[0], dict):
                self._from_dict(args[0])
            elif isinstance(args[0], str):
                try:
                    self._from_formula(args[0], mass_data)
                except PyteomicsError:
                    raise PyteomicsError(
                        'Could not create a Composition object from '
                        'string: "{}": not a valid sequence or '
                        'formula'.format(args[0]))
        else:
            self._from_dict(kwargs)
        self._mass = None
        self._mass_args = None

Composition = CComposition


@cython.wraparound(False)
@cython.boundscheck(False)
cpdef inline double calculate_mass(CComposition composition=None, str formula=None, int average=False, charge=None, mass_data=None) except -1:
    """Calculates the monoisotopic mass of a chemical formula or CComposition object.

    Parameters
    ----------
    composition : CComposition
        A Composition object with the elemental composition of a substance. Exclusive with `formula`
    formula: str
        A string describing a chemical composition. Exclusive with `composition`
    average : bool, optional
        If :py:const:`True` then the average mass is calculated. Note that mass
        is not averaged for elements with specified isotopes. Default is
        :py:const:`False`.
    charge : int, optional
        If not 0 then m/z is calculated: the mass is increased
        by the corresponding number of proton masses and divided
        by z.
    mass_data : dict, optional
        A dict with the masses of the chemical elements (the default
        value is :py:data:`nist_mass`).

    Returns
    -------
        mass : float
    """
    cdef:
        int old_charge, isotope_num, isotope, quantity
        double mass, isotope_mass, isotope_frequency
        long _charge
        str isotope_string, element_name
        dict mass_provider
        list key_list
        PyObject* interm
        Py_ssize_t iter_pos = 0

    if mass_data is None:
        mass_provider = nist_mass
    else:
        mass_provider = mass_data

    if composition is None:
        if formula is not None:
            composition = CComposition(formula)
        else:
            raise PyteomicsError("Must provide a composition or formula argument")
    else:
        if formula is not None:
            raise PyteomicsError("Must provide a composition or formula argument, but not both")

    # Get charge.
    if charge is None:
        charge = composition.getitem('H+')
    else:
        if charge != 0 and composition.getitem('H+') != 0:
            raise PyteomicsError("Charge is specified both by the number of protons and parameters")
    _charge = PyInt_AsLong(charge)
    old_charge = composition.getitem('H+')
    composition.setitem('H+', charge)

    # Calculate mass.
    mass = 0.0
    key_list = PyDict_Keys(composition)
    for iter_pos in range(len(key_list)):
        isotope_string = <str>PyList_GET_ITEM(key_list, iter_pos)
        # element_name, isotope_num = _parse_isotope_string(isotope_string)
        element_name = _parse_isotope_string(isotope_string, &isotope_num)

        # Calculate average mass if required and the isotope number is
        # not specified.
        if (not isotope_num) and average:
            for isotope in mass_provider[element_name]:
                if isotope != 0:
                    quantity = <int>composition.getitem(element_name)
                    isotope_mass = <double>mass_provider[element_name][isotope][0]
                    isotope_frequency = <double>mass_provider[element_name][isotope][1]

                    mass += quantity * isotope_mass * isotope_frequency
        else:
            interim = PyDict_GetItem(mass_provider, element_name)
            interim = PyDict_GetItem(<dict>interim, isotope_num)
            isotope_mass = PyFloat_AsDouble(<object>PyTuple_GetItem(<tuple>interim, 0))

            mass += (composition.getitem(isotope_string) * isotope_mass)

    # Calculate m/z if required.
    if _charge != 0:
        mass /= _charge

    composition.setitem('H+', old_charge)
    return mass

Composition = CComposition
