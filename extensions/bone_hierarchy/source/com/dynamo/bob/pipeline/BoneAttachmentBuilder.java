package com.dynamo.bob.pipeline;

import com.dynamo.bob.Builder;
import com.dynamo.bob.BuilderParams;
import com.dynamo.bob.Task;
import com.dynamo.bob.fs.IResource;
import com.dynamo.lua.proto.Lua.LuaModule;
import com.dynamo.script.proto.Lua.LuaSource;
import com.google.protobuf.ByteString;
import java.io.IOException;

/** The authoring component has no runtime callbacks or model dependency. */
@BuilderParams(name="BoneAttachment", inExts={".boneattachment"}, outExt=".scriptc")
public class BoneAttachmentBuilder extends Builder {
    public static byte[] marker() {
        return LuaModule.newBuilder().setSource(LuaSource.newBuilder()
            .setFilename("@boneattachment")
            .setScript(ByteString.copyFromUtf8("-- BoneAttachment: editor authoring only\n")))
            .build().toByteArray();
    }
    @Override public Task create(IResource input) {
        return Task.newBuilder(this).setName(params.name()).addInput(input)
            .addOutput(input.changeExt(params.outExt())).build();
    }
    @Override public void build(Task task) throws IOException {
        task.output(0).setContent(marker());
    }
}
