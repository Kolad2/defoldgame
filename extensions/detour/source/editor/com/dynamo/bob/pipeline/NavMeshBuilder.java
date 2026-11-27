package com.dynamo.bob.pipeline;

import com.dynamo.bob.Builder;
import com.dynamo.bob.BuilderParams;
import com.dynamo.bob.Task;
import com.dynamo.bob.CompileExceptionError;
import com.dynamo.bob.fs.IResource;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import com.defold.navmesh.NavMeshResource;

/** Embeds the source mesh and component settings in the game's resource. */
@BuilderParams(name="NavMesh", inExts={".navmesh"}, outExt=".navmeshc")
public class NavMeshBuilder extends Builder {
    @Override public Task create(IResource input) throws IOException, CompileExceptionError {
        JsonNode config;
        try { config = new ObjectMapper().readTree(input.getContent()); }
        catch (Exception e) { throw new CompileExceptionError(input, 0, "Invalid NavMesh JSON: " + e.getMessage()); }
        String path = config.path("source").asText("");
        if (!path.startsWith("/") || !path.endsWith(".bin"))
            throw new CompileExceptionError(input, 0, "NavMesh source must be a project /path/file.bin");
        IResource source = project.getResource(path);
        if (!source.exists()) throw new CompileExceptionError(input, 0, "NavMesh source not found: " + path);
        Task.TaskBuilder task = Task.newBuilder(this).setName(params.name()).addInput(input).addInput(source)
            .addOutput(input.changeExt(params.outExt()));
        createSubTask(project.getResource("/detour/resources/navmesh.material"), task);
        createSubTask(project.getResource("/detour/resources/navmesh_xray.material"), task);
        return task.build();
    }
    @Override public void build(Task task) throws IOException, CompileExceptionError {
        try {
            task.output(0).setContent(NavMeshResource.compile(task.input(0).getContent(), task.input(1).getContent(),
                "/detour/resources/navmesh.materialc", "/detour/resources/navmesh_xray.materialc"));
        } catch (Exception e) {
            throw new CompileExceptionError(task.input(0), 0, e.getMessage());
        }
    }
}
