### cut columns 1 and 3 from t2g tsv #########
import gzip

def get_flank_length(file,read_length_frx):
    with gzip.open(file,"r") as rf:
        head = [next(rf) for x in range(4)]
    read_length = len(head[1])
    flank_length = int( read_length_frx * read_length )
    return(flank_length)  

rule cut_t2g:
        input:
            "Annotation/genes.filtered.t2g"
        output:
            "Annotation/genes.filtered.slim.t2g"
        threads: 1
        shell:"""
            cut -f1,3 {input[0]} > {output[0]}
            """

rule SalmonAlevin:
        input:
            R2 = "originalFASTQ/{sample}"+reads[0]+".fastq.gz",
            R1 = "originalFASTQ/{sample}"+reads[1]+".fastq.gz",
            bin = "Salmon/SalmonIndex/seq.bin"
        params:
            protocol = "--" + prepProtocol,
            whitelist = "--whitelist {}".format(BCwhiteList) if BCwhiteList else "",
            expectcells = "--expectcells {}".format(expectCells) if expectCells else "",
            tgMap = "Annotation/genes.filtered.slim.t2g",
            libtype = alevinLibraryType,
            outdir = "Alevin/{sample}"
        output:
            quantmat = "Alevin/{sample}/alevin/quants_mat.gz",
        log: 
            out =  "Alevin/logs/alevin.{sample}.out",
            err = "Alevin/logs/alevin.{sample}.err"
        #Use RNAseq env because Salmon already installed there (no need for duplication).
        conda: CONDA_RNASEQ_ENV
        threads: 8
        shell:"""
            salmon alevin -l {params.libtype} -1 {input.R1} -2 {input.R2} {params.protocol} -i Salmon/SalmonIndex -p {threads} -o {params.outdir} --tgMap {params.tgMap} --dumpFeatures --dumpMtx --numCellBootstraps 100 > {log.out} 2> {log.err}
            """

rule AlevinQC:
        input:
            indum = "Alevin/{sample}/alevin/quants_mat.gz"
        output:
            outfiles = "multiQC/Alevin_{sample}.html"
        params:
            indir = "Alevin/{sample}/",
            outdir =  "multiQC/",
            samid = "{sample}",
            outfile = "Alevin_{sample}.html"
        conda: CONDA_alevinqc_ENV
        script: "../rscripts/scRNAseq_Alevinqc.R"


##### the code for obtaining spliced/unspliced counts from Alevin is based on Soneson et al.2020, bioRxiv, https://doi.org/10.1101/2020.03.13.990069

rule run_eisaR:
    input:
        gtf = "Annotation/genes.filtered.gtf",
        fasta = genome_fasta
    output:
        joint_fasta = "Annotation/cDNA_introns.joint.fa",
        joint_t2g = "Annotation/cDNA_introns.joint.t2g"
    params:
        wdir = os.path.join(wdir, "Annotation"),
        scriptdir = workflow_rscripts,
        isoform_action = "separate",
        flank_length = get_flank_length(os.path.join(wdir,"originalFASTQ/"+samples[0]+reads[0]+ext),read_length_frx)
    log:
        out = "Annotation/logs/eisaR.out"
    conda: CONDA_eisaR_ENV
    script: "../rscripts/scRNAseq_eisaR.R"



#uses decoys generated by rule SalmonIndex in Salmon.snakefile

rule Salmon_index_joint_fa:
    input:
        joint_fasta = "Annotation/cDNA_introns.joint.fa",
        decoys = "Salmon/SalmonIndex/decoys.txt",
        genome_fasta = genome_fasta
    output:
        seq_fa = temp("Salmon/SalmonIndex_RNAVelocity/seq.fa")
        salmon_index = "Salmon/SalmonIndex_RNAVelocity/seq.bin"
    log:
        err = "Salmon/SalmonIndex_RNAVelocity/logs/SalmonIndex.err"
        out = "Salmon/SalmonIndex_RNAVelocity/logs/SalmonIndex.out"
    threads: 8
    conda: CONDA_RNASEQ_ENV
    shell:"""
        cat {input.joint_fasta} {input.genome_fasta} > {output.seq_fa}
        salmon index -p {threads} -t {output.seq_fa} -d {input.decoys} -i Salmon/SalmonIndex_RNAVelocity {params.salmonIndexOptions} > {log.out} 2> {log.err}
        """

rule AlevinForVelocity:
        input:
            R2 = "originalFASTQ/{sample}"+reads[0]+".fastq.gz",
            R1 = "originalFASTQ/{sample}"+reads[1]+".fastq.gz",
            bin = "Salmon/SalmonIndex_RNAVelocity/seq.bin",
            tgMap = "Annotation/Annotation/cDNA_introns.joint.t2g"
        params:
            protocol = "--" + prepProtocol,
            whitelist = "--whitelist {}".format(BCwhiteList) if BCwhiteList else "",
            expectcells = "--expectcells {}".format(expectCells) if expectCells else "",
            libtype = alevinLibraryType,
            outdir = "AlevinForVelocity/{sample}"
        output:
            quantmat = "AlevinForVelocity/{sample}/alevin/quants_mat.gz"
        log: 
            out =  "AlevinForVelocity/logs/alevin.{sample}.out",
            err = "AlevinForVelocity/logs/alevin.{sample}.err"
        #Use RNAseq env because Salmon already installed there (no need for duplication).
        conda: CONDA_RNASEQ_ENV
        threads: 8
        shell:"""
            salmon alevin -l {params.libtype} -1 {input.R1} -2 {input.R2} {params.protocol} -i Salmon/SalmonIndex_RNAVelocity -p {threads} -o {params.outdir} --tgMap {input.tgMap} --dumpFeatures --dumpMtx --numCellBootstraps 100 > {log.out} 2> {log.err}
            """

#rule split_matrices:
#    input:
#        quantmat = "AlevinForVelocity/{sample}/alevin/quants_mat.gz"
#    output:
#        spliced = ""
#        unspliced = ""
#    script: "../rscripts/scRNAseq_splitAlevinVelocityMatrices.R"


