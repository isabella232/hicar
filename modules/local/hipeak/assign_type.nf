// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from '../functions'

params.options = [:]
options        = initOptions(params.options)

process ASSIGN_TYPE {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), meta:meta, publish_by_meta:['id']) }

    conda (params.enable_conda ? "bioconda::bioconductor-chippeakanno=3.26.0" : null)
    if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
        container "https://depot.galaxyproject.org/singularity/bioconductor-chippeakanno:3.26.0--r41hdfd78af_0"
    } else {
        container "quay.io/biocontainers/bioconductor-chippeakanno:3.26.0--r41hdfd78af_0"
    }

    input:
    tuple val(meta), path(counts)

    output:
    tuple val(meta), path("${meta.id}/summary.*.txt"), optional: true, emit: summary
    tuple val(meta), path("${meta.id}/*.peaks"), optional: true, emit: peak
    tuple val(meta), path("${meta.id}/*.bedpe"), optional: true, emit: bedpe
    path "*.version.txt"          , emit: version

    script:
    def software = "CALL_HIPEAK"
    """
    install_packages.r graph RBGL InteractionSet
    assign_interaction_type.r $options.args \\
        --interactions $counts --output ${meta.id}
    """
}
