"""``snakemake`` file that runs entire analysis."""

# Imports ---------------------------------------------------------------------
import glob
import itertools
import os.path
import textwrap
import urllib.request

import Bio.SeqIO

import dms_variants.codonvarianttable
import dms_variants.illuminabarcodeparser

import pandas as pd

# Configuration  --------------------------------------------------------------
configfile: 'config.yaml'

# run "quick" rules locally:
localrules: make_rulegraph,
            make_summary

# Functions -------------------------------------------------------------------
def nb_markdown(nb):
    """Return path to Markdown results of notebook `nb`."""
    return os.path.join(config['summary_dir'],
                        os.path.basename(os.path.splitext(nb)[0]) + '.md')

# Global variables extracted from config --------------------------------------
pacbio_runs = (pd.read_csv(config['pacbio_runs'], dtype = str)
               .assign(pacbioRun=lambda x: x['library'] + '_' + x['run'])
               )
assert len(pacbio_runs['pacbioRun'].unique()) == len(pacbio_runs['pacbioRun'])

# Information on samples and barcode runs -------------------------------------
barcode_runs = pd.read_csv(config['barcode_runs'])

# combination of the *library* and *sample* columns should be unique.
assert len(barcode_runs.groupby(['library', 'sample'])) == len(barcode_runs)

# *sample* should be the hyphen separated concatenation of
# *experiment*, *antibody*, *concentration*, and *sort_bin*.
# only check this for ab_selection experiments;
# hope that the SortSeq and TiteSeq experiments are ok
sample_vs_expect = (
    barcode_runs
    .query('experiment_type=="ab_selection"')
    .assign(concentration=lambda x: x['concentration'].astype(int),
            expect=lambda x: x[['experiment', 'antibody', 'concentration',
                                'sort_bin']]
                             .apply(lambda r: '-'.join(r.values.astype(str)),
                                    axis=1),
            equal=lambda x: x['sample'] == x['expect'],
            )
    )
assert sample_vs_expect['equal'].all(), sample_vs_expect.query('equal != True')

# barcode runs with R1 files expanded by glob
barcode_runs_expandR1 = (
    barcode_runs
    .assign(R1=lambda x: x['R1'].str.split('; ').map(
                    lambda y: list(itertools.chain(*map(glob.glob, y)))),
            n_R1=lambda x: x['R1'].map(len),
            sample_lib=lambda x: x['sample'] + '_' + x['library'],
            )
    )

assert barcode_runs_expandR1['sample_lib'].nunique() == len(barcode_runs_expandR1)
if any(barcode_runs_expandR1['n_R1'] < 1):
    raise ValueError(f"no R1 for {barcode_runs_expandR1.query('n_R1 < 1')}")

# Rules -----------------------------------------------------------------------

# this is the target rule (in place of `all`) since it first rule listed
rule make_summary:
    """Create Markdown summary of analysis."""
    input:
        rulegraph=os.path.join(config['summary_dir'], 'rulegraph.svg'),
        get_early2020_mut_bind_expr=config['early2020_mut_bind_expr'],
        get_early2020_escape_fracs=config['early2020_escape_fracs'],
        get_beta_escape_fracs=config['beta_escape_fracs'],
        get_beta_mut_bind_expr=config['beta_mut_bind_expr'],
        bind_expr_filters=nb_markdown('bind_expr_filters.ipynb'),
        process_ccs=nb_markdown('process_ccs.ipynb'),
        build_variants=nb_markdown('build_variants.ipynb'),
        codon_variant_table=config['codon_variant_table'],
        aggregate_variant_counts=nb_markdown('aggregate_variant_counts.ipynb'),
        variant_counts=config['variant_counts'],
        fit_titrations='results/summary/compute_binding_Kd.md',
        variant_Kds_file=config['Titeseq_Kds_file'],
        calculate_expression='results/summary/compute_expression_meanF.md',
        variant_expression_file=config['expression_sortseq_file'],
        collapse_scores='results/summary/collapse_scores.md',
        mut_phenos_file=config['final_variant_scores_mut_file'],
        counts_to_cells_ratio=nb_markdown('counts_to_cells_ratio.ipynb'),
        counts_to_cells_csv=config['counts_to_cells_csv'],
        counts_to_scores=nb_markdown('counts_to_scores.ipynb'),
        escape_fracs=config['escape_fracs'],
        investigate_scores=nb_markdown('investigate_scores.ipynb'),
        call_strong_escape_sites=nb_markdown('call_strong_escape_sites.ipynb'),
        strong_escape_sites=config['strong_escape_sites'],
        escape_profiles=nb_markdown('escape_profiles.ipynb'),
        early2020_call_strong_escape_sites=nb_markdown('early2020_call_strong_escape_sites.ipynb'),
        early2020_strong_escape_sites=config['early2020_strong_escape_sites'],
        early2020_escape_profiles=nb_markdown('early2020_escape_profiles.ipynb'),
        mds_escape_profiles=nb_markdown('mds_escape_profiles.ipynb'),
        output_pdbs=nb_markdown('output_pdbs.ipynb'),
        make_supp_data=nb_markdown('make_supp_data.ipynb'),
        lineplots_by_group=nb_markdown('lineplots_by_group.ipynb'),
        gisaid_rbd_mutations=nb_markdown('gisaid_rbd_mutations.ipynb'),
        gisaid_mutation_counts=config['gisaid_mutation_counts'],
        natural_mutations=nb_markdown('natural_mutations.ipynb'),
        aggregate_escape_scores_file=config['aggregate_escape_scores_file'],
    output:
        summary = os.path.join(config['summary_dir'], 'summary.md')
    run:
        def path(f):
            """Get path relative to `summary_dir`."""
            return os.path.relpath(f, config['summary_dir'])
        with open(output.summary, 'w') as f:
            f.write(textwrap.dedent(f"""
            # Summary

            Analysis run by [Snakefile]({path(workflow.snakefile)})
            using [this config file]({path(workflow.configfiles[0])}).
            See the [README in the top directory]({path('README.md')})
            for details.

            Here is the rule graph of the computational workflow:
            ![{path(input.rulegraph)}]({path(input.rulegraph)})

            Here is the Markdown output of each notebook in the workflow:
            1. Get prior DMS mutation-level [binding and expression data]({path(input.get_early2020_mut_bind_expr)}).

            2. Get prior MAPping [escape_fracs]({path(input.get_early2020_escape_fracs)}) for polyclonal plasmas from early 2020 against the Wuhan-1 RBD library.

            3. Get prior DMS mutation-level [binding and expression data]({path(input.get_beta_mut_bind_expr)}) and MAPping [escape_fracs]({path(input.get_beta_escape_fracs)}) for polyclonal plasmas from Beta infections against the Beta RBD DMS library.

            2. [Process PacBio CCSs]({path(input.process_ccs)}).

            3. [Build variants from CCSs]({path(input.build_variants)}).
               Creates a [codon variant table]({path(input.codon_variant_table)})
               linking barcodes to the mutations in the variants.

            4. Count variants and then
                [aggregate counts]({path(input.aggregate_variant_counts)})
                to create [variant counts file]({path(input.variant_counts)}).

            5. [Analyze sequencing counts to cells ratio]({path(input.counts_to_cells_ratio)});
               this prints a list of any samples where this ratio too low. Also
               creates [a CSV]({path(input.counts_to_cells_csv)}) with the
               sequencing counts, number of sorted cells, and ratios for
               all samples.

            6. [Fit titration curves]({path(input.fit_titrations)}) to calculate per-barcode K<sub>D</sub>, recorded in [this file]({path(input.variant_Kds_file)}).

            7. [Analyze Sort-seq]({path(input.calculate_expression)}) to calculate per-barcode RBD expression, recorded in [this file]({path(input.variant_expression_file)}).

            8. [Derive final genotype-level phenotypes from replicate barcoded sequences]({path(input.collapse_scores)}).
               Generates final phenotypes, recorded in [this file]({path(input.mut_phenos_file)}).

            9. Determine [cutoffs]({path(input.bind_expr_filters)}) for ACE2 binding and RBD expression for serum-escape experiments.

            10. [Escape scores from variant counts]({path(input.counts_to_scores)}).

            11. [Investigate scores]({path(input.investigate_scores)}) before applying ACE2 binding and RBD expression filters, to see if there is a relationship between functional scores and serum-escape score.

            11. [Call sites of strong escape]({path(input.call_strong_escape_sites)}),
               and write to [a CSV file]({path(input.strong_escape_sites)}).

            12. Plot [escape profiles]({path(input.escape_profiles)}).

            13. Map escape profiles to ``*.pdb`` files using [this notebook]({path(input.output_pdbs)})

            14. [Make supplementary data files]({path(input.make_supp_data)}),
                 which are [here]({path(config['supp_data_dir'])}). These include
                 `dms-view` input files.

            13. [Count mutations in GISAID RBD sequences]({path(input.gisaid_rbd_mutations)})
                to create [this counts file]({path(input.gisaid_mutation_counts)}).

            14. [Analyze GISAID mutations at sites of escape]({path(input.natural_mutations)}).

            15. Make [lineplots by serum group]({path(input.lineplots_by_group)}).

            16. [Multidimensional scaling]({path(input.mds_escape_profiles)}) on escape profiles.

            17. Aggregate escape scores from all studies and all DMS libraries and output to a [supplementary file]({path(input.aggregate_escape_scores_file)}).

            """
            ).strip())

rule make_rulegraph:
    # error message, but works: https://github.com/sequana/sequana/issues/115
    input:
        workflow.snakefile
    output:
        os.path.join(config['summary_dir'], 'rulegraph.svg')
    shell:
        "snakemake --forceall --rulegraph | dot -Tsvg > {output}"

rule aggregate_escape_scores:
    input:
        config['early2020_escape_fracs'],
        config['beta_escape_fracs'],
        config['escape_fracs'],
    output:
        config['aggregate_escape_scores_file'],
        nb_markdown=nb_markdown('aggregate_escape_scores.ipynb'),
    params:
        nb='aggregate_escape_scores.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule natural_mutations:
    input:
        config['gisaid_mutation_counts'],
        config['strong_escape_sites'],
        config['escape_fracs'],
        config['escape_profiles_config'],
    output:
        nb_markdown=nb_markdown('natural_mutations.ipynb')
    params:
        nb='natural_mutations.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule gisaid_rbd_mutations:
    input:
        config['gisaid_spikes'],
        config['wildtype_sequence'],
    output:
        config['gisaid_mutation_counts'],
        nb_markdown=nb_markdown('gisaid_rbd_mutations.ipynb'),
    params:
        nb='gisaid_rbd_mutations.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule mds_escape_profiles:
    """Multi-dimensional scaling on antibody escape profiles."""
    input:
        config['early2020_escape_fracs'],
        config['beta_escape_fracs'],
        escape_fracs=config['escape_fracs'],
        mds_config=config['mds_config'],
        site_color_schemes=config['site_color_schemes'],
    output:
        nb_markdown=nb_markdown('mds_escape_profiles.ipynb'),
    params:
        nb='mds_escape_profiles.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule lineplots_by_group:
    input:
        config['early2020_escape_fracs'],
        config['beta_escape_fracs'],
        config['escape_fracs'],
        "data/pdbs/6M0J.pdb",
    output:
        nb_markdown=nb_markdown('lineplots_by_group.ipynb'),
        outdir=directory(config['lineplots_by_group_dir']),
    params:
        nb='lineplots_by_group.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"


rule make_supp_data:
    input:
        config['escape_profiles_config'],
        config['output_pdbs_config'],
        config['escape_fracs'],
        config['escape_profiles_dms_colors']
    output:
        nb_markdown=nb_markdown('make_supp_data.ipynb'),
        # outdir=directory(config['supp_data_dir']),
    params:
        nb='make_supp_data.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule output_pdbs:
    input:
        config['escape_fracs'],
        config['output_pdbs_config'],
    output:
        nb_markdown=nb_markdown('output_pdbs.ipynb'),
        outdir=directory(config['pdb_outputs_dir']),
    params:
        nb='output_pdbs.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule escape_profiles:
    """Make stacked logo plots of antibody escape profiles."""
    input:
        escape_fracs=config['escape_fracs'],
        escape_profiles_config=config['escape_profiles_config'],
        site_color_schemes=config['site_color_schemes'],
        wildtype_sequence=config['wildtype_sequence'],
        mut_bind_expr=config['final_variant_scores_mut_file'],
        strong_escape_sites=config['strong_escape_sites'],
    output:
        nb_markdown=nb_markdown('escape_profiles.ipynb'),
        escape_profiles_dms_colors=config['escape_profiles_dms_colors'],
    params:
        nb='escape_profiles.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule call_strong_escape_sites:
    """Call sites of strong escape."""
    input:
        escape_fracs=config['escape_fracs'],
    output:
        nb_markdown=nb_markdown('call_strong_escape_sites.ipynb'),
        strong_escape_sites=config['strong_escape_sites'],
    params:
        nb='call_strong_escape_sites.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule investigate_scores:
    """Investigate relationship between RBD expression, ACE2 binding, and serum-escape scores."""
    input:
        config['final_variant_scores_mut_file'],
        config['escape_scores'],
    output:
        nb_markdown=nb_markdown('investigate_scores.ipynb'),
    params:
        nb='investigate_scores.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule counts_to_scores:
    """Analyze variant counts to compute escape scores."""
    input:
        config['variant_counts'],
        config['wildtype_sequence'],
        config['final_variant_scores_mut_file'],
    output:
        nb_markdown=nb_markdown('counts_to_scores.ipynb'),
        escape_scores=config['escape_scores'],
        escape_score_samples=config['escape_score_samples'],
        escape_fracs=config['escape_fracs'],
    params:
        nb='counts_to_scores.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule counts_to_cells_ratio:
    input:
        config['variant_counts'],
        config['barcode_runs'],
        config['wildtype_sequence'],
    output:
        nb_markdown=nb_markdown('counts_to_cells_ratio.ipynb'),
        counts_to_cells_csv=config['counts_to_cells_csv'],
    params:
        nb='counts_to_cells_ratio.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule bind_expr_filters:
    """QC checks on bind & expression filters from DMS data.
    """
    input:
        config['final_variant_scores_mut_file'],
        config['early2020_escape_fracs']
    output:
        nb_markdown=nb_markdown('bind_expr_filters.ipynb')
    params:
        nb='bind_expr_filters.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule collapse_scores:
    input:
        config['Titeseq_Kds_file'],
        config['expression_sortseq_file'],
    output:
        config['final_variant_scores_mut_file'],
        md='results/summary/collapse_scores.md',
        md_files=directory('results/summary/collapse_scores_files')
    envmodules:
        'R/3.6.2-foss-2019b'
    params:
        nb='collapse_scores.Rmd',
        md='collapse_scores.md',
        md_files='collapse_scores_files'
    shell:
        """
        R -e \"rmarkdown::render(input=\'{params.nb}\')\";
        mv {params.md} {output.md};
        mv {params.md_files} {output.md_files}
        """

rule fit_titrations:
    input:
        config['codon_variant_table'],
        # config['variant_counts'] # temporarily commented out so is not re-run every time I get serum mapping data back
    output:
        config['Titeseq_Kds_file'],
        md='results/summary/compute_binding_Kd.md',
        md_files=directory('results/summary/compute_binding_Kd_files')
    envmodules:
        'R/3.6.2-foss-2019b'
    params:
        nb='compute_binding_Kd.Rmd',
        md='compute_binding_Kd.md',
        md_files='compute_binding_Kd_files'
    shell:
        """
        R -e \"rmarkdown::render(input=\'{params.nb}\')\";
        mv {params.md} {output.md};
        mv {params.md_files} {output.md_files}
        """

rule calculate_expression:
    input:
        config['codon_variant_table'],
        # config['variant_counts'] # temporarily commented out so is not re-run every time I get serum mapping data back
    output:
        config['expression_sortseq_file'],
        md='results/summary/compute_expression_meanF.md',
        md_files=directory('results/summary/compute_expression_meanF_files')
    envmodules:
        'R/3.6.2-foss-2019b'
    params:
        nb='compute_expression_meanF.Rmd',
        md='compute_expression_meanF.md',
        md_files='compute_expression_meanF_files'
    shell:
        """
        R -e \"rmarkdown::render(input=\'{params.nb}\')\";
        mv {params.md} {output.md};
        mv {params.md_files} {output.md_files}
        """

rule aggregate_variant_counts:
    input:
        counts=expand(os.path.join(config['counts_dir'],
                                   "{sample_lib}_counts.csv"),
                      sample_lib=barcode_runs_expandR1['sample_lib']),
        fates=expand(os.path.join(config['counts_dir'],
                                  "{sample_lib}_fates.csv"),
                     sample_lib=barcode_runs_expandR1['sample_lib']),
        variant_table=config['codon_variant_table'],
        wt_seq=config['wildtype_sequence'],
        barcode_runs=config['barcode_runs'],
    output:
        config['variant_counts'],
        nb_markdown=nb_markdown('aggregate_variant_counts.ipynb')
    params:
        nb='aggregate_variant_counts.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule count_variants:
    """Count variants for a specific sample."""
    input:
        variant_table=config['codon_variant_table'],
        wt_seq=config['wildtype_sequence'],
        r1s=lambda wildcards: (barcode_runs_expandR1
                               .set_index('sample_lib')
                               .at[wildcards.sample_lib, 'R1']
                               ),
    output:
        counts=os.path.join(config['counts_dir'], "{sample_lib}_counts.csv"),
        fates=os.path.join(config['counts_dir'], "{sample_lib}_fates.csv"),
    params:
        sample_lib="{sample_lib}"
    run:
        # parse sample and library from `sample_lib` wildcard
        lib = params.sample_lib.split('_')[-1]
        sample = params.sample_lib[: -len(lib) - 1]
        assert sample == (barcode_runs_expandR1
                          .set_index('sample_lib')
                          .at[params.sample_lib, 'sample']
                          )
        assert lib == (barcode_runs_expandR1
                       .set_index('sample_lib')
                       .at[params.sample_lib, 'library']
                       )
        # initialize `CodonVariantTable` (used to get valid barcodes)
        wt_seqrecord = Bio.SeqIO.read(input.wt_seq, 'fasta')
        geneseq = str(wt_seqrecord.seq)
        primary_target = wt_seqrecord.name
        variants=dms_variants.codonvarianttable.CodonVariantTable(
                    geneseq=geneseq,
                    barcode_variant_file=input.variant_table,
                    substitutions_are_codon=True,
                    substitutions_col='codon_substitutions',
                    primary_target=primary_target)
        # initialize `IlluminaBarcodeParser`
        parser = dms_variants.illuminabarcodeparser.IlluminaBarcodeParser(
                    valid_barcodes=variants.valid_barcodes(lib),
                    **config['illumina_barcode_parser_params'])
        # parse barcodes
        counts, fates = parser.parse(input.r1s,
                                     add_cols={'library': lib,
                                               'sample': sample})
        # write files
        counts.to_csv(output.counts, index=False)
        fates.to_csv(output.fates, index=False)

rule build_variants:
    """Build variant table from processed CCSs."""
    input:
        config['processed_ccs_file']
    output:
        config['codon_variant_table'],
        nb_markdown=nb_markdown('build_variants.ipynb')
    params:
        nb='build_variants.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule early2020_escape_profiles:
    """Make stacked logo plots of antibody escape profiles for early 2020 samples."""
    input:
        escape_fracs=config['early2020_escape_fracs'],
        escape_profiles_config=config['early2020_escape_profiles_config'],
        site_color_schemes=config['site_color_schemes'],
        wildtype_sequence=config['early2020_wildtype_sequence'],
        early2020_mut_bind_expr=config['early2020_mut_bind_expr'],
        strong_escape_sites=config['early2020_strong_escape_sites'],
    output:
        nb_markdown=nb_markdown('early2020_escape_profiles.ipynb'),
        escape_profiles_dms_colors=config['early2020_escape_profiles_dms_colors'],
    params:
        nb='early2020_escape_profiles.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule early2020_call_strong_escape_sites:
    """Call sites of strong escape for early 2020 samples."""
    input:
        escape_fracs=config['early2020_escape_fracs'],
    output:
        nb_markdown=nb_markdown('early2020_call_strong_escape_sites.ipynb'),
        strong_escape_sites=config['early2020_strong_escape_sites'],
    params:
        nb='early2020_call_strong_escape_sites.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

rule get_beta_escape_fracs:
    """Download escape_fracs for Beta polyclonal plasmas
        against Wuhan-1 RBD library from URL and
        Download SARS-CoV-2 Beta mutation ACE2-binding and expression from URL.
    """
    output:
        beta_escape_fracs=config['beta_escape_fracs'],
        beta_mut_bind_expr=config['beta_mut_bind_expr']
    run:
        urllib.request.urlretrieve(config['beta_escape_fracs_url'], output.beta_escape_fracs)
        urllib.request.urlretrieve(config['beta_mut_bind_expr_url'], output.beta_mut_bind_expr)

rule get_early2020_escape_fracs:
    """Download escape_fracs for early 2020 polyclonal plasmas
        against Wuhan-1 RBD library from URL.
    """
    output:
        file=config['early2020_escape_fracs']
    run:
        urllib.request.urlretrieve(config['early2020_escape_fracs_url'], output.file)

rule get_early2020_mut_bind_expr:
    """Download SARS-CoV-2 Wuhan-1 mutation ACE2-binding and expression from URL."""
    output:
        file=config['early2020_mut_bind_expr']
    run:
        urllib.request.urlretrieve(config['early2020_mut_bind_expr_url'], output.file)

rule process_ccs:
    """Process the PacBio CCSs."""
    input:
        expand(os.path.join(config['ccs_dir'], "{pacbioRun}_ccs.fastq.gz"),
               pacbioRun=pacbio_runs['pacbioRun']),
        config['amplicons'],
    output:
        config['processed_ccs_file'],
        nb_markdown=nb_markdown('process_ccs.ipynb')
    params:
        nb='process_ccs.ipynb'
    shell:
        "python scripts/run_nb.py {params.nb} {output.nb_markdown}"

if config['seqdata_source'] == 'HutchServer':

    rule get_ccs:
        """Symbolically link CCS files."""
        input:
            ccs_fastq=lambda wildcards: (pacbio_runs
                                        .set_index('pacbioRun')
                                        .at[wildcards.pacbioRun, 'ccs']
                                        )
        output:
            ccs_fastq=os.path.join(config['ccs_dir'], "{pacbioRun}_ccs.fastq.gz")
        run:
            os.symlink(input.ccs_fastq, output.ccs_fastq)

elif config['seqdata_source'] == 'SRA':
    raise RuntimeError('getting sequence data from SRA not yet implemented')

else:
    raise ValueError(f"invalid `seqdata_source` {config['seqdata_source']}")
