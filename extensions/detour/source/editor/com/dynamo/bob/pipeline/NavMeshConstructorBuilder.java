package com.dynamo.bob.pipeline;

import com.dynamo.bob.Builder;
import com.dynamo.bob.BuilderParams;
import com.dynamo.bob.Task;
import com.dynamo.bob.fs.IResource;
import com.defold.navmesh.NavMeshConstructor;
import java.io.IOException;

/** Authoring component: no GLB, Java/JNI baker or bake configuration reaches the game. */
@BuilderParams(name="NavMeshConstructor",inExts={".navmeshconstructor"},outExt=".scriptc")
public class NavMeshConstructorBuilder extends Builder {
    @Override public Task create(IResource input) {
        return Task.newBuilder(this).setName(params.name()).addInput(input).addOutput(input.changeExt(params.outExt())).build();
    }
    @Override public void build(Task task) throws IOException { task.output(0).setContent(NavMeshConstructor.marker()); }
}
