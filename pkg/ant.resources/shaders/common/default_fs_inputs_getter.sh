
{
    fs_input.frag_coord = gl_FragCoord;
    fs_input.uv0 = v_texcoord0;
#ifndef MATERIAL_UNLIT
    fs_input.normal = v_normal;
    fs_input.pos    = v_posWS;
    #ifndef CALC_TBN
        fs_input.tangent = v_tangent;
    #endif   //CALC_TBN
#endif //MATERIAL_UNLIT

#ifdef WITH_COLOR_ATTRIB
    fs_input.color = v_color0;
#endif //WITH_COLOR_ATTRIB

#if defined(USING_LIGHTMAP)
    fs_input.uv1 = v_texcoord1;
#endif //USING_LIGHTMAP

#ifdef OUTPUT_USER_ATTR_0
    fs_input.user0 = v_texcoord6;
#endif //OUTPUT_USER_ATTR_0

#ifdef OUTPUT_USER_ATTR_1
    fs_input.user1 = v_texcoord7;
#endif //OUTPUT_USER_ATTR_1

#ifdef OUTPUT_USER_ATTR_2
    fs_input.user2 = v_texcoord8;
#endif //OUTPUT_USER_ATTR_2

#ifdef OUTPUT_USER_ATTR_3
    fs_input.user3 = v_texcoord9;
#endif //OUTPUT_USER_ATTR_3

#ifdef OUTPUT_USER_ATTR_4
    fs_input.user4 = v_texcoord10;
#endif //OUTPUT_USER_ATTR_4
}